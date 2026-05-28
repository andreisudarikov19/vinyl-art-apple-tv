import Foundation
import SwiftData

/// Resolves higher-quality covers for cached releases via MusicBrainz +
/// Cover Art Archive, falling back to the Discogs cover already stored.
///
/// Runs on its own background context so the gallery stays responsive during
/// the (rate-limited, potentially long) first pass. Each release is only
/// attempted once — `coverLookupAttempted` guards re-querying MusicBrainz for
/// the whole collection on every launch.
@ModelActor
actor CoverArtService {
    func resolvePending(limit: Int = .max) async {
        let descriptor = FetchDescriptor<CachedRelease>(
            predicate: #Predicate { !$0.coverLookupAttempted }
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else {
            return
        }

        let musicBrainz = MusicBrainzClient()
        var processed = 0

        for release in pending {
            if processed >= limit { break }
            processed += 1

            release.resolvedCoverURL = await resolvedCover(for: release, using: musicBrainz)
            release.coverLookupAttempted = true
            try? modelContext.save()
        }
    }

    /// Resolves a single release on demand (e.g. when its record screen opens),
    /// so its cover is replaced immediately rather than waiting for the sweep.
    /// No-op if the release is missing or already attempted.
    func resolveOne(releaseId: Int) async {
        let descriptor = FetchDescriptor<CachedRelease>(
            predicate: #Predicate { $0.releaseId == releaseId && !$0.coverLookupAttempted }
        )
        guard let release = try? modelContext.fetch(descriptor).first else { return }

        release.resolvedCoverURL = await resolvedCover(for: release, using: MusicBrainzClient())
        release.coverLookupAttempted = true
        try? modelContext.save()
    }

    private func resolvedCover(for release: CachedRelease, using musicBrainz: MusicBrainzClient) async -> String? {
        guard let match = await musicBrainz.bestMatch(
            artist: release.artistDisplayName,
            title: release.title,
            catalogNumber: release.catalogNumber
        ) else { return nil }

        if let url = await CoverArtArchive.frontCoverURL(forRelease: match.releaseMBID) {
            return url
        }
        if let groupMBID = match.releaseGroupMBID,
           let url = await CoverArtArchive.frontCoverURL(forReleaseGroup: groupMBID) {
            return url
        }
        return nil
    }
}
