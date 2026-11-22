import Foundation
import SwiftData

/// Finds a year for the releases Discogs gives none, which the Gallery
/// otherwise files under "Unknown".
///
/// It asks two places, in this order:
/// 1. The Discogs master release, the album every pressing belongs to. The
///    link is exact: the collection gives each release its master's ID.
/// 2. MusicBrainz, with the same search the cover lookup uses (artist, title
///    and catalogue number), for a release with no master or a master with no
///    year.
///
/// What it finds is a year of the album, which need not be the year of the
/// pressing on the shelf, so it is kept apart in `CachedRelease.albumYear`
/// and Discogs' own year always wins.
///
/// A release is marked `yearLookupAttempted` once it has a definite answer, a
/// year or none. A failure that a retry might cure (offline, rate limited,
/// signed out) leaves it for the next launch.
///
/// Conforms to `ModelActor` by hand, like `CoverArtService`: the macro's own
/// initialiser can't set the injected dependencies.
actor ReleaseYearService: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor: any ModelExecutor

    /// The sweep stops after this many failures in a row, which means the
    /// device is offline or a service is down. The next launch resumes it.
    static let maxConsecutiveFailures = 3

    private let masterYear: @Sendable (Int) async throws -> Int?
    private let musicBrainz: MusicBrainzClient

    /// - Parameters:
    ///   - musicBrainz: Shared by default, so this and the cover lookups keep
    ///     to one rate limit.
    ///   - masterYear: The year of a Discogs master release, nil when it has
    ///     none. Throws when Discogs couldn't answer.
    init(
        modelContainer: ModelContainer,
        musicBrainz: MusicBrainzClient = .shared,
        masterYear: @escaping @Sendable (Int) async throws -> Int?
    ) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.musicBrainz = musicBrainz
        self.masterYear = masterYear
    }

    private enum Answer {
        case year(Int)
        case none
        /// No answer this time; worth another try at the next launch.
        case later
    }

    func resolvePending() async {
        let descriptor = FetchDescriptor<CachedRelease>(
            predicate: #Predicate { $0.year == 0 && !$0.yearLookupAttempted }
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }

        var consecutiveFailures = 0
        for release in pending {
            switch await lookUp(release) {
            case .year(let year):
                release.albumYear = year
                release.yearLookupAttempted = true
                consecutiveFailures = 0
            case .none:
                release.yearLookupAttempted = true
                consecutiveFailures = 0
            case .later:
                consecutiveFailures += 1
            }
            // Saved one by one, so each record takes its place on the scale
            // as soon as its year is known.
            try? modelContext.save()
            if consecutiveFailures >= Self.maxConsecutiveFailures { break }
        }
    }

    private func lookUp(_ release: CachedRelease) async -> Answer {
        // Discogs gives 0 for a release with no master.
        if let master = release.masterId, master > 0 {
            do {
                if let year = try await masterYear(master) { return .year(year) }
            } catch let error as DiscogsClientError {
                switch error {
                case .unauthorized, .rateLimited, .invalidResponse:
                    return .later
                case .httpError(let status, _) where status >= 500:
                    return .later
                case .httpError, .decodingFailed:
                    // A master that is gone or unreadable: on to MusicBrainz.
                    break
                }
            } catch {
                // The request didn't complete.
                return .later
            }
        }

        do {
            let match = try await musicBrainz.bestMatch(
                artist: release.artistDisplayName,
                title: release.title,
                catalogNumber: release.catalogNumber
            )
            if let year = match?.year { return .year(year) }
            return .none
        } catch {
            return .later
        }
    }
}
