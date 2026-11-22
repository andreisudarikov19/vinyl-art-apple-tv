import Foundation
import Nuke
import os
import SwiftData
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct CoverArtServiceTests {
    private typealias Responder = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CachedRelease.self, UserPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Pauses are recorded in `pauses` instead of slept, and MusicBrainz
    /// requests aren't spaced out, so the tests don't wait. Images load
    /// through the stub too, with no disk cache, and a memory cache of their
    /// own, so one test's pictures don't answer another's URLs.
    private func makeService(
        _ container: ModelContainer,
        pauses: OSAllocatedUnfairLock<[Duration]> = .init(initialState: [])
    ) -> CoverArtService {
        let session = StubSession.make()
        var configuration = ImagePipeline.Configuration(dataLoader: DataLoader(configuration: StubSession.configuration()))
        configuration.dataCache = nil
        configuration.imageCache = ImageCache()
        return CoverArtService(
            modelContainer: container,
            musicBrainz: MusicBrainzClient(session: session, interval: .zero),
            coverArtSession: session,
            imagePipeline: ImagePipeline(configuration: configuration),
            sleep: { duration in pauses.withLock { $0.append(duration) } }
        )
    }

    private static let red = (r: UInt8(200), g: UInt8(80), b: UInt8(60))
    private static let blue = (r: UInt8(60), g: UInt8(80), b: UInt8(200))

    /// The Discogs cover of release 1 is a 600px red sleeve.
    private var discogsRed600: Data {
        flatPNG(width: 600, height: 600, red: Self.red.r, green: Self.red.g, blue: Self.red.b)
    }

    /// Stores a pending release per entry, with that many failed lookups.
    /// Release n is titled "Title n". Each is saved on its own, so the store
    /// keeps them in this order unless a fetch sorts them.
    private func seedPending(_ container: ModelContainer, failures: [Int]) throws {
        let context = ModelContext(container)
        for (index, count) in failures.enumerated() {
            let id = index + 1
            context.insert(CachedRelease(
                releaseId: id,
                instanceId: id * 10,
                title: "Title \(id)",
                artistDisplayName: "Artist",
                year: 2020,
                dateAdded: .distantPast,
                discogsCoverURL: "https://example.com/\(id).jpg",
                thumbURL: "https://example.com/thumb.jpg",
                coverLookupFailures: count
            ))
            try context.save()
        }
    }

    private func storedReleases(_ container: ModelContainer) throws -> [CachedRelease] {
        try ModelContext(container).fetch(FetchDescriptor<CachedRelease>(sortBy: [SortDescriptor(\.releaseId)]))
    }

    /// Routes stubbed requests by host. By default the Cover Art Archive has
    /// no art. `images` answers the image URLs it names with their bytes.
    private func stub(
        musicBrainz: @escaping Responder,
        coverArtArchive: @escaping Responder = { (stubHTTPResponse(for: $0, statusCode: 404), Data()) },
        images: [String: Data] = [:]
    ) {
        StubURLProtocol.responder = { request in
            if request.url?.host == "musicbrainz.org" {
                return try musicBrainz(request)
            }
            if let url = request.url?.absoluteString, let data = images[url] {
                return (stubHTTPResponse(for: request), data)
            }
            return try coverArtArchive(request)
        }
    }

    /// Stores a release with its Discogs cover and, optionally, a resolved
    /// archive cover judged under `coverRuleVersion`.
    private func seedJudged(
        _ container: ModelContainer,
        id: Int,
        resolved: String?,
        coverRuleVersion: Int
    ) throws {
        let context = ModelContext(container)
        context.insert(CachedRelease(
            releaseId: id,
            instanceId: id * 10,
            title: "Title \(id)",
            artistDisplayName: "Artist",
            year: 2020,
            dateAdded: .distantPast,
            discogsCoverURL: discogsCoverURL(id),
            thumbURL: "https://example.com/thumb.jpg",
            resolvedCoverURL: resolved,
            coverLookupAttempted: true,
            coverRuleVersion: coverRuleVersion
        ))
        try context.save()
    }

    private static let match: Responder = { request in
        (stubHTTPResponse(for: request), musicBrainzSearchJSON(releases: [("match", 100)]))
    }
    private static let noMatch: Responder = { request in
        (stubHTTPResponse(for: request), musicBrainzSearchJSON(releases: []))
    }
    private static let unavailable: Responder = { request in
        (stubHTTPResponse(for: request, statusCode: 503), Data())
    }

    @Test func noMatchMarksTheReleaseAttempted() async throws {
        stub(musicBrainz: Self.noMatch)
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.coverLookupAttempted)
        #expect(release.resolvedCoverURL == nil)
    }

    @Test func unavailableLookupStaysPendingAndCountsAFailure() async throws {
        stub(musicBrainz: Self.unavailable)
        let container = try makeContainer()
        try seedPending(container, failures: [0])
        let pauses = OSAllocatedUnfairLock(initialState: [Duration]())

        await makeService(container, pauses: pauses).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(!release.coverLookupAttempted)
        #expect(release.coverLookupFailures == 1)
        #expect(pauses.withLock { $0 }.isEmpty)
    }

    @Test func thirdUnavailableLookupMarksTheReleaseAttempted() async throws {
        stub(musicBrainz: Self.unavailable)
        let container = try makeContainer()
        try seedPending(container, failures: [2])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.coverLookupAttempted)
        #expect(release.coverLookupFailures == 3)
        #expect(release.resolvedCoverURL == nil)
    }

    @Test func offlineLookupStaysPendingWithoutCountingAFailure() async throws {
        stub(musicBrainz: { _ in throw URLError(.notConnectedToInternet) })
        let container = try makeContainer()
        try seedPending(container, failures: [1])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(!release.coverLookupAttempted)
        #expect(release.coverLookupFailures == 1)
    }

    @Test func releaseWithoutArtFallsBackToItsReleaseGroup() async throws {
        let groupCover = "https://archive.example.com/group.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            if request.url?.path == "/release-group/match-group" {
                return (stubHTTPResponse(for: request), coverArtListingJSON(image: groupCover))
            }
            return (stubHTTPResponse(for: request, statusCode: 404), Data())
        }, images: [
            discogsCoverURL(1): discogsRed600,
            groupCover: flatPNG(width: 1200, height: 1200, red: Self.red.r, green: Self.red.g, blue: Self.red.b),
        ])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == groupCover)
        #expect(release.coverLookupAttempted)
        #expect(release.coverRuleVersion == CoverArtService.coverRuleVersion)
    }

    @Test func archiveImageOfTheSamePictureReplacesTheDiscogsCover() async throws {
        let archive = "https://archive.example.com/front.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            (stubHTTPResponse(for: request), coverArtListingJSON(image: archive))
        }, images: [
            discogsCoverURL(1): discogsRed600,
            archive: flatPNG(width: 1200, height: 1200, red: Self.red.r, green: Self.red.g, blue: Self.red.b),
        ])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == archive)
        #expect(release.coverLookupAttempted)
        #expect(release.coverRuleVersion == CoverArtService.coverRuleVersion)
    }

    @Test func archiveImageOfAnotherPressingKeepsTheDiscogsCover() async throws {
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            (stubHTTPResponse(for: request), coverArtListingJSON(image: "https://archive.example.com/other.jpg"))
        }, images: [
            discogsCoverURL(1): discogsRed600,
            "https://archive.example.com/other.jpg":
                flatPNG(width: 1200, height: 1200, red: Self.blue.r, green: Self.blue.g, blue: Self.blue.b),
        ])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == nil)
        #expect(release.preferredCoverURL == URL(string: discogsCoverURL(1)))
        #expect(release.coverLookupAttempted)
        #expect(release.coverRuleVersion == CoverArtService.coverRuleVersion)
    }

    @Test func releaseGroupImageOfAnotherPressingKeepsTheDiscogsCover() async throws {
        let groupCover = "https://archive.example.com/group.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            if request.url?.path == "/release-group/match-group" {
                return (stubHTTPResponse(for: request), coverArtListingJSON(image: groupCover))
            }
            return (stubHTTPResponse(for: request, statusCode: 404), Data())
        }, images: [
            discogsCoverURL(1): discogsRed600,
            groupCover: flatPNG(width: 1200, height: 1200, red: Self.blue.r, green: Self.blue.g, blue: Self.blue.b),
        ])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == nil)
        #expect(release.coverLookupAttempted)
    }

    @Test func archiveImageNotClearlyLargerKeepsTheDiscogsCover() async throws {
        let archive = "https://archive.example.com/small.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            (stubHTTPResponse(for: request), coverArtListingJSON(image: archive))
        }, images: [
            discogsCoverURL(1): discogsRed600,
            archive: flatPNG(width: 700, height: 700, red: Self.red.r, green: Self.red.g, blue: Self.red.b),
        ])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == nil)
        #expect(release.coverLookupAttempted)
    }

    @Test func archiveImageThatCannotBeLoadedKeepsTheDiscogsCover() async throws {
        let archive = "https://archive.example.com/gone.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            (stubHTTPResponse(for: request), coverArtListingJSON(image: archive))
        }, images: [discogsCoverURL(1): discogsRed600])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == nil)
        #expect(release.coverLookupAttempted)
    }

    @Test func unavailableArchiveImageStaysPendingAndCountsAFailure() async throws {
        let archive = "https://archive.example.com/busy.jpg"
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            if request.url?.host == "archive.example.com" {
                return (stubHTTPResponse(for: request, statusCode: 503), Data())
            }
            return (stubHTTPResponse(for: request), coverArtListingJSON(image: archive))
        }, images: [discogsCoverURL(1): discogsRed600])
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(!release.coverLookupAttempted)
        #expect(release.coverLookupFailures == 1)
        #expect(release.resolvedCoverURL == nil)
    }

    @Test func coversResolvedUnderAnOlderRuleAreJudgedOnceMore() async throws {
        let other = "https://archive.example.com/other.jpg"
        let same = "https://archive.example.com/same.jpg"
        let requested = OSAllocatedUnfairLock(initialState: [String]())
        StubURLProtocol.responder = { request in
            let url = request.url?.absoluteString ?? ""
            requested.withLock { $0.append(url) }
            switch url {
            case discogsCoverURL(2):
                return (stubHTTPResponse(for: request), discogsRed600)
            case other:
                return (stubHTTPResponse(for: request), flatPNG(width: 1200, height: 1200, red: Self.blue.r, green: Self.blue.g, blue: Self.blue.b))
            case same:
                return (stubHTTPResponse(for: request), flatPNG(width: 1200, height: 1200, red: Self.red.r, green: Self.red.g, blue: Self.red.b))
            case discogsCoverURL(1):
                return (stubHTTPResponse(for: request), discogsRed600)
            default:
                return (stubHTTPResponse(for: request, statusCode: 404), Data())
            }
        }
        let container = try makeContainer()
        try seedJudged(container, id: 1, resolved: other, coverRuleVersion: 0)
        try seedJudged(container, id: 2, resolved: same, coverRuleVersion: 0)
        try seedJudged(container, id: 3, resolved: nil, coverRuleVersion: 0)
        let service = makeService(container)

        await service.rejudgeResolvedCovers()

        let releases = try storedReleases(container)
        #expect(releases.map(\.resolvedCoverURL) == [nil, same, nil])
        #expect(releases.map(\.coverRuleVersion) == [1, 1, 0])
        // Release 3 has no archive cover, so there is nothing to judge.
        #expect(requested.withLock { $0 }.allSatisfy { !$0.contains(discogsCoverURL(3)) })

        requested.withLock { $0 = [] }
        await service.rejudgeResolvedCovers()
        #expect(requested.withLock { $0 }.isEmpty)
    }

    @Test func unavailableCoverArtArchiveStaysPendingWithoutTryingTheGroup() async throws {
        let paths = OSAllocatedUnfairLock(initialState: [String]())
        stub(musicBrainz: Self.match, coverArtArchive: { request in
            paths.withLock { $0.append(request.url?.path ?? "") }
            return try Self.unavailable(request)
        })
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(!release.coverLookupAttempted)
        #expect(release.coverLookupFailures == 1)
        #expect(paths.withLock { $0 } == ["/release/match"])
    }

    @Test func sweepStopsAfterThreeTransientFailuresInARow() async throws {
        let searches = OSAllocatedUnfairLock(initialState: 0)
        stub(musicBrainz: { request in
            searches.withLock { $0 += 1 }
            return try Self.unavailable(request)
        })
        let container = try makeContainer()
        try seedPending(container, failures: [0, 0, 0, 0, 0])
        let pauses = OSAllocatedUnfairLock(initialState: [Duration]())

        await makeService(container, pauses: pauses).resolvePending()

        #expect(searches.withLock { $0 } == 3)
        #expect(try storedReleases(container).map(\.coverLookupFailures).sorted() == [0, 0, 1, 1, 1])
        // One pause before each of the next two releases; none once it stops.
        #expect(pauses.withLock { $0 } == [CoverArtService.failurePause, CoverArtService.failurePause])
    }

    @Test func sweepTriesReleasesWithFewerFailuresFirst() async throws {
        let queries = OSAllocatedUnfairLock(initialState: [String]())
        stub(musicBrainz: { request in
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "query" })?.value
            queries.withLock { $0.append(query ?? "") }
            return try Self.noMatch(request)
        })
        let container = try makeContainer()
        try seedPending(container, failures: [2, 0, 1])

        await makeService(container).resolvePending()

        let expected = [2, 3, 1].map { "release:\"Title \($0)\" AND artist:\"Artist\"" }
        #expect(queries.withLock { $0 } == expected)
    }
}

/// The Discogs cover seeded for release `id` by `seedPending`.
private func discogsCoverURL(_ id: Int) -> String {
    "https://example.com/\(id).jpg"
}
