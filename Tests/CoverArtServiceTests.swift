import Foundation
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
    /// requests aren't spaced out, so the tests don't wait.
    private func makeService(
        _ container: ModelContainer,
        pauses: OSAllocatedUnfairLock<[Duration]> = .init(initialState: [])
    ) -> CoverArtService {
        let session = StubSession.make()
        return CoverArtService(
            modelContainer: container,
            musicBrainz: MusicBrainzClient(session: session, interval: .zero),
            coverArtSession: session,
            sleep: { duration in pauses.withLock { $0.append(duration) } }
        )
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
    /// no art.
    private func stub(
        musicBrainz: @escaping Responder,
        coverArtArchive: @escaping Responder = { (stubHTTPResponse(for: $0, statusCode: 404), Data()) }
    ) {
        StubURLProtocol.responder = { request in
            if request.url?.host == "musicbrainz.org" {
                return try musicBrainz(request)
            }
            return try coverArtArchive(request)
        }
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
        })
        let container = try makeContainer()
        try seedPending(container, failures: [0])

        await makeService(container).resolveOne(releaseId: 1)

        let release = try #require(storedReleases(container).first)
        #expect(release.resolvedCoverURL == groupCover)
        #expect(release.coverLookupAttempted)
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
