import Foundation
import SwiftData
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct CollectionSyncServiceTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CachedRelease.self, UserPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeClient() -> DiscogsClient {
        DiscogsClient(
            credentials: DiscogsCredentials(
                username: "tester",
                accessToken: "token",
                accessTokenSecret: "secret"
            ),
            urlSession: StubSession.make()
        )
    }

    @Test func fullBuildStoresOnlyVinylAcrossPages() async throws {
        StubURLProtocol.responder = { request in
            let data: Data
            switch requestedPage(request) {
            case 1:
                data = collectionPageJSON(page: 1, pages: 2, items: 3, releases: [
                    releaseJSON(id: 1, dateAdded: "2024-03-01T00:00:00-00:00", format: "Vinyl"),
                    releaseJSON(id: 2, dateAdded: "2024-02-01T00:00:00-00:00", format: "CD"),
                ])
            default:
                data = collectionPageJSON(page: 2, pages: 2, items: 3, releases: [
                    releaseJSON(id: 3, dateAdded: "2024-01-01T00:00:00-00:00", format: "Vinyl"),
                ])
            }
            return (stubHTTPResponse(for: request), data)
        }

        let container = try makeContainer()
        let service = CollectionSyncService(modelContainer: container)
        let summary = try await service.sync(using: makeClient())

        #expect(summary.mode == .fullBuild)
        #expect(summary.storedReleaseCount == 2)
        #expect(summary.totalCollectionItems == 3)

        let stored = try ModelContext(container).fetch(FetchDescriptor<CachedRelease>())
        #expect(Set(stored.map(\.releaseId)) == [1, 3])
    }

    @Test func deltaStopsAtAlreadySyncedReleases() async throws {
        let container = try makeContainer()
        do {
            let context = ModelContext(container)
            context.insert(UserPreferences(
                discogsUsername: "tester",
                lastSyncDate: CachedRelease.parseDate("2024-02-01T00:00:00-00:00")
            ))
            try context.save()
        }

        StubURLProtocol.responder = { request in
            let data = collectionPageJSON(page: 1, pages: 1, items: 2, releases: [
                releaseJSON(id: 1, dateAdded: "2024-03-01T00:00:00-00:00", format: "Vinyl"),
                releaseJSON(id: 2, dateAdded: "2024-01-01T00:00:00-00:00", format: "Vinyl"),
            ])
            return (stubHTTPResponse(for: request), data)
        }

        let service = CollectionSyncService(modelContainer: container)
        let summary = try await service.sync(using: makeClient())

        #expect(summary.mode == .delta)
        #expect(summary.storedReleaseCount == 1)

        let stored = try ModelContext(container).fetch(FetchDescriptor<CachedRelease>())
        #expect(stored.map(\.releaseId) == [1])
    }

    @Test func reSyncUpdatesMetadataButPreservesResolvedCover() async throws {
        let container = try makeContainer()
        do {
            let context = ModelContext(container)
            context.insert(CachedRelease(
                releaseId: 1,
                instanceId: 10,
                title: "Old Title",
                artistDisplayName: "Artist",
                year: 2019,
                dateAdded: .distantPast,
                discogsCoverURL: "https://example.com/old.jpg",
                thumbURL: "https://example.com/thumb.jpg",
                resolvedCoverURL: "https://archive.example.com/resolved.jpg",
                coverLookupAttempted: true
            ))
            try context.save()
        }

        StubURLProtocol.responder = { request in
            let data = collectionPageJSON(page: 1, pages: 1, items: 1, releases: [
                releaseJSON(
                    id: 1,
                    dateAdded: "2024-03-01T00:00:00-00:00",
                    format: "Vinyl",
                    title: "New Title",
                    coverImage: "https://example.com/new.jpg"
                ),
            ])
            return (stubHTTPResponse(for: request), data)
        }

        let service = CollectionSyncService(modelContainer: container)
        _ = try await service.sync(using: makeClient(), forceFullBuild: true)

        let stored = try ModelContext(container).fetch(FetchDescriptor<CachedRelease>())
        #expect(stored.count == 1)
        let release = try #require(stored.first)
        #expect(release.title == "New Title")
        #expect(release.discogsCoverURL == "https://example.com/new.jpg")
        #expect(release.resolvedCoverURL == "https://archive.example.com/resolved.jpg")
        #expect(release.coverLookupAttempted == true)
    }

    @Test func fullBuildPrunesReleasesNoLongerInCollection() async throws {
        let container = try makeContainer()
        do {
            let context = ModelContext(container)
            context.insert(CachedRelease(
                releaseId: 99,
                instanceId: 990,
                title: "Removed",
                artistDisplayName: "Artist",
                year: 2000,
                dateAdded: .distantPast,
                discogsCoverURL: "https://example.com/x.jpg",
                thumbURL: "https://example.com/thumb.jpg"
            ))
            try context.save()
        }

        StubURLProtocol.responder = { request in
            let data = collectionPageJSON(page: 1, pages: 1, items: 1, releases: [
                releaseJSON(id: 1, dateAdded: "2024-03-01T00:00:00-00:00", format: "Vinyl"),
            ])
            return (stubHTTPResponse(for: request), data)
        }

        let service = CollectionSyncService(modelContainer: container)
        _ = try await service.sync(using: makeClient(), forceFullBuild: true)

        let stored = try ModelContext(container).fetch(FetchDescriptor<CachedRelease>())
        #expect(Set(stored.map(\.releaseId)) == [1])
    }
}
