import Foundation
import SwiftData

/// Resolves higher-quality covers for cached releases via MusicBrainz +
/// Cover Art Archive, falling back to the Discogs cover already stored.
///
/// Runs on its own background context so the gallery stays responsive during
/// the (rate-limited, potentially long) first pass. A release is marked
/// `coverLookupAttempted` once it gets a definite answer, a cover or none, so
/// the whole collection isn't re-queried against MusicBrainz on every launch.
/// A transient failure leaves it pending for a later try, up to
/// `maxLookupFailures`.
///
/// Conforms to `ModelActor` by hand: the `@ModelActor` macro always adds its
/// own `init(modelContainer:)`, which can't set the injected dependencies.
actor CoverArtService: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    /// After this many 429 or 5xx answers a release is marked attempted and
    /// keeps its Discogs cover. Network errors don't count.
    static let maxLookupFailures = 3

    /// The sweep stops after this many transient failures in a row, which
    /// means the device is offline or MusicBrainz is down. The next launch
    /// resumes it.
    static let maxConsecutiveFailures = 3

    /// How long the sweep waits after a transient failure before trying the
    /// next release.
    static let failurePause: Duration = .seconds(10)

    private let musicBrainz: MusicBrainzClient
    private let coverArtSession: URLSession
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - musicBrainz: Shared by default, so the sweep and every on-demand
    ///     lookup keep to one rate limit.
    ///   - sleep: How the sweep pauses after a transient failure. Tests pass
    ///     one that returns at once.
    init(
        modelContainer: ModelContainer,
        musicBrainz: MusicBrainzClient = .shared,
        coverArtSession: URLSession = .shared,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.musicBrainz = musicBrainz
        self.coverArtSession = coverArtSession
        self.sleep = sleep
    }

    func resolvePending(limit: Int = .max) async {
        // Fewest failures first, so one stubborn release doesn't hold up the
        // rest.
        let descriptor = FetchDescriptor<CachedRelease>(
            predicate: #Predicate { !$0.coverLookupAttempted },
            sortBy: [SortDescriptor(\.coverLookupFailures)]
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else {
            return
        }

        var processed = 0
        var consecutiveFailures = 0

        for release in pending {
            if processed >= limit { break }
            processed += 1

            if consecutiveFailures > 0 {
                try? await sleep(Self.failurePause)
            }
            if await resolve(release) {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                if consecutiveFailures >= Self.maxConsecutiveFailures { break }
            }
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

        await resolve(release)
    }

    /// Looks up `release`'s cover and records the outcome. Returns false if
    /// the lookup failed for a transient reason.
    @discardableResult
    private func resolve(_ release: CachedRelease) async -> Bool {
        defer { try? modelContext.save() }
        do throws(CoverLookup.Failure) {
            release.resolvedCoverURL = try await resolvedCover(for: release)
            release.coverLookupAttempted = true
            return true
        } catch .unavailable {
            release.coverLookupFailures += 1
            if release.coverLookupFailures >= Self.maxLookupFailures {
                release.coverLookupAttempted = true
            }
            return false
        } catch {
            // .network: being offline isn't the release's fault.
            return false
        }
    }

    /// Returns nil when there is definitely no cover: no MusicBrainz match,
    /// or no art for the release or its release group.
    private func resolvedCover(for release: CachedRelease) async throws(CoverLookup.Failure) -> String? {
        guard let match = try await musicBrainz.bestMatch(
            artist: release.artistDisplayName,
            title: release.title,
            catalogNumber: release.catalogNumber
        ) else { return nil }

        if let url = try await CoverArtArchive.frontCoverURL(forRelease: match.releaseMBID, session: coverArtSession) {
            return url
        }
        if let groupMBID = match.releaseGroupMBID,
           let url = try await CoverArtArchive.frontCoverURL(forReleaseGroup: groupMBID, session: coverArtSession) {
            return url
        }
        return nil
    }
}
