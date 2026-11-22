import Foundation
import Nuke
import SwiftData

/// Resolves higher-quality covers for cached releases via MusicBrainz +
/// Cover Art Archive, falling back to the Discogs cover already stored.
///
/// An archive image replaces the Discogs cover only when `CoverChoice` says
/// it is better. That needs both pictures, so the decision is made after the
/// archive image has loaded, and it is stored on the release. Spec 07.
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

    /// The version of the cover rule (`CoverChoice`) that decides a release's
    /// cover. A release records the version it was judged under. Bump this to
    /// judge every resolved cover once more, at the next sweep.
    static let coverRuleVersion = 1

    private let musicBrainz: MusicBrainzClient
    private let coverArtSession: URLSession
    private let imagePipeline: ImagePipeline
    private let sleep: @Sendable (Duration) async throws -> Void

    /// - Parameters:
    ///   - musicBrainz: Shared by default, so the sweep and every on-demand
    ///     lookup keep to one rate limit.
    ///   - imagePipeline: Loads both pictures for `CoverChoice`. The shared
    ///     pipeline keeps the archive image it decodes, which the screens
    ///     then show without a second download. Tests pass one on a stub.
    ///   - sleep: How the sweep pauses after a transient failure. Tests pass
    ///     one that returns at once.
    init(
        modelContainer: ModelContainer,
        musicBrainz: MusicBrainzClient = .shared,
        coverArtSession: URLSession = .shared,
        imagePipeline: ImagePipeline = .shared,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.musicBrainz = musicBrainz
        self.coverArtSession = coverArtSession
        self.imagePipeline = imagePipeline
        self.sleep = sleep
    }

    func resolvePending(limit: Int = .max) async {
        await rejudgeResolvedCovers()

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

    /// Judges the covers that were resolved under an older rule, once. A
    /// release whose `coverRuleVersion` is behind keeps its archive cover only
    /// if `CoverChoice` still prefers it. A transient failure stops the pass,
    /// and the next launch resumes it, since the unjudged releases keep their
    /// old version.
    func rejudgeResolvedCovers() async {
        let version = Self.coverRuleVersion
        let descriptor = FetchDescriptor<CachedRelease>(
            predicate: #Predicate { $0.resolvedCoverURL != nil && $0.coverRuleVersion < version }
        )
        guard let releases = try? modelContext.fetch(descriptor) else { return }

        for release in releases {
            guard let archive = release.resolvedCoverURL else { continue }
            do throws(CoverLookup.Failure) {
                let keepsArchive = try await prefersArchive(discogs: release.discogsCoverURL, archive: archive)
                if !keepsArchive {
                    release.resolvedCoverURL = nil
                }
                release.coverRuleVersion = version
            } catch {
                return
            }
            try? modelContext.save()
        }
    }

    /// Looks up `release`'s cover and records the outcome. Returns false if
    /// the lookup failed for a transient reason.
    @discardableResult
    private func resolve(_ release: CachedRelease) async -> Bool {
        defer { try? modelContext.save() }
        do throws(CoverLookup.Failure) {
            release.resolvedCoverURL = try await resolvedCover(for: release)
            release.coverLookupAttempted = true
            release.coverRuleVersion = Self.coverRuleVersion
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

    /// Returns nil when the Discogs cover stays: no MusicBrainz match, no
    /// front art for the release or its release group, or an archive image
    /// that `CoverChoice` refuses (another pressing, say).
    private func resolvedCover(for release: CachedRelease) async throws(CoverLookup.Failure) -> String? {
        guard let match = try await musicBrainz.bestMatch(
            artist: release.artistDisplayName,
            title: release.title,
            catalogNumber: release.catalogNumber
        ) else { return nil }

        let archive: String?
        if let url = try await CoverArtArchive.frontCoverURL(forRelease: match.releaseMBID, session: coverArtSession) {
            archive = url
        } else if let groupMBID = match.releaseGroupMBID,
                  let url = try await CoverArtArchive.frontCoverURL(forReleaseGroup: groupMBID, session: coverArtSession) {
            // Release-group art is held to the same test: another pressing's
            // sleeve is refused like any other.
            archive = url
        } else {
            archive = nil
        }

        guard let url = archive else { return nil }
        return try await prefersArchive(discogs: release.discogsCoverURL, archive: url) ? url : nil
    }

    /// Loads both pictures and asks `CoverChoice`. An image that can't be had
    /// and won't come back on a retry (a 404, bytes that don't decode) counts
    /// as a refusal. A transient failure throws.
    private func prefersArchive(discogs: String, archive: String) async throws(CoverLookup.Failure) -> Bool {
        guard let discogsImage = try await candidate(for: discogs),
              let archiveImage = try await candidate(for: archive)
        else { return false }

        // The archive lookup only returns images marked as the front cover.
        return CoverChoice.prefersArchive(discogs: discogsImage, archive: archiveImage, archiveIsFront: true)
    }

    private func candidate(for urlString: String) async throws(CoverLookup.Failure) -> CoverChoice.Candidate? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let image = try await imagePipeline.image(for: url)
            guard let cgImage = image.cgImage else { return nil }
            return CoverChoice.Candidate(cgImage)
        } catch {
            if let failure = Self.transientFailure(of: error) {
                throw failure
            }
            return nil
        }
    }

    /// Sorts a failed image load into one a retry may change and one it
    /// won't. Nil means the picture is not coming back this time either.
    private static func transientFailure(of error: Error) -> CoverLookup.Failure? {
        if error is CancellationError { return .network }
        guard let pipelineError = error as? ImagePipeline.Error,
              case .dataLoadingFailed(let underlying) = pipelineError
        else { return nil }

        if let loadError = underlying as? DataLoader.Error,
           case .statusCodeUnacceptable(let code) = loadError {
            return code == 429 || code >= 500 ? .unavailable : nil
        }
        return underlying is URLError ? .network : nil
    }
}
