import Foundation
import SwiftData

/// Progress emitted while building or refreshing the library, sized to drive
/// the "Fetching 247/812 albums…" screen.
struct SyncProgress: Sendable, Equatable {
    /// Releases paged through so far (all formats, not just vinyl).
    var processed: Int
    /// Total items reported by Discogs for the collection.
    var total: Int
}

struct SyncSummary: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        /// First launch or a manual "Refresh collection": every page is read
        /// and releases no longer in the collection are pruned.
        case fullBuild
        /// Subsequent launch: read newest pages until reaching already-synced
        /// releases, then stop.
        case delta
    }

    var mode: Mode
    /// Vinyl releases inserted or updated this run.
    var storedReleaseCount: Int
    var totalCollectionItems: Int
}

/// Pages through the Discogs collection and mirrors the vinyl releases into
/// SwiftData. Runs on its own background context via `@ModelActor` so large
/// first-launch builds don't block the main thread.
@ModelActor
actor CollectionSyncService {
    func sync(
        using client: DiscogsClient,
        forceFullBuild: Bool = false,
        onProgress: @Sendable (SyncProgress) -> Void = { _ in }
    ) async throws -> SyncSummary {
        let startedAt = Date()
        let preferences = UserPreferences.current(in: modelContext)
        let lastSync = preferences.lastSyncDate
        let mode: SyncSummary.Mode = (forceFullBuild || lastSync == nil) ? .fullBuild : .delta

        var existing: [Int: CachedRelease] = [:]
        for release in try modelContext.fetch(FetchDescriptor<CachedRelease>()) {
            existing[release.releaseId] = release
        }

        var seenVinylIDs: Set<Int> = []
        var processed = 0
        var stored = 0
        var reachedAlreadySynced = false

        func ingest(_ page: DiscogsCollectionPage, total: Int) {
            for release in page.releases {
                processed += 1
                if mode == .delta, let lastSync,
                   CachedRelease.parseDate(release.dateAdded) <= lastSync {
                    reachedAlreadySynced = true
                    break
                }
                guard release.basicInformation.isVinyl else { continue }
                seenVinylIDs.insert(release.id)
                if let current = existing[release.id] {
                    current.apply(release)
                } else {
                    let cached = CachedRelease(from: release)
                    modelContext.insert(cached)
                    existing[release.id] = cached
                }
                stored += 1
            }
            onProgress(SyncProgress(processed: processed, total: total))
        }

        let firstPage = try await client.collectionPage(page: 1)
        let totalItems = firstPage.pagination.items
        ingest(firstPage, total: totalItems)

        if !reachedAlreadySynced, firstPage.pagination.pages > 1 {
            for page in 2...firstPage.pagination.pages {
                ingest(try await client.collectionPage(page: page), total: totalItems)
                if reachedAlreadySynced { break }
            }
        }

        if mode == .fullBuild {
            for (id, release) in existing where !seenVinylIDs.contains(id) {
                modelContext.delete(release)
            }
        }

        preferences.lastSyncDate = startedAt
        preferences.discogsUsername = client.username
        try modelContext.save()

        return SyncSummary(
            mode: mode,
            storedReleaseCount: stored,
            totalCollectionItems: totalItems
        )
    }
}
