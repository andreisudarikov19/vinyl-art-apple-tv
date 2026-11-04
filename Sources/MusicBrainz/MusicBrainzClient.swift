import Foundation

/// A MusicBrainz release match, used to look up cover art.
struct MusicBrainzMatch: Sendable {
    let releaseMBID: String
    let releaseGroupMBID: String?
}

/// Searches MusicBrainz for the release that best matches a cached Discogs
/// release. MusicBrainz asks clients to stay under 1 request/second and to
/// send a descriptive User-Agent, both of which this actor enforces.
actor MusicBrainzClient {
    /// The client every cover lookup uses, so the launch sweep and the record
    /// screens' on-demand lookups keep to one rate limit between them.
    static let shared = MusicBrainzClient()

    /// The least search score, out of 100, trusted as the same release, so a
    /// common title doesn't pick up another record's cover.
    static let minimumScore = 90

    private let session: URLSession
    private let interval: Duration
    /// When the latest request goes out; ahead of now while callers wait for
    /// their slots.
    private var lastRequestAt: ContinuousClock.Instant?

    /// - Parameter interval: The least time between requests. Tests pass a
    ///   short one.
    init(session: URLSession = .shared, interval: Duration = .seconds(1.1)) {
        self.session = session
        self.interval = interval
    }

    /// Returns the highest-scoring release at or above `minimumScore`, nil
    /// when there is none, and throws when MusicBrainz couldn't answer this
    /// time.
    func bestMatch(
        artist: String,
        title: String,
        catalogNumber: String?
    ) async throws(CoverLookup.Failure) -> MusicBrainzMatch? {
        guard !title.isEmpty else { return nil }

        var lucene = "release:\(quoted(title)) AND artist:\(quoted(artist))"
        if let catalogNumber, !catalogNumber.isEmpty {
            lucene += " AND catno:\(quoted(catalogNumber))"
        }

        guard var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: lucene),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return nil }

        await throttle()

        guard let result = try await CoverLookup.fetch(SearchResult.self, from: url, session: session) else {
            return nil
        }
        // A missing score counts as 0. Ties keep MusicBrainz' order.
        let trusted = result.releases.filter { ($0.score ?? 0) >= Self.minimumScore }
        guard let release = trusted.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else { return nil }

        return MusicBrainzMatch(
            releaseMBID: release.id,
            releaseGroupMBID: release.releaseGroup?.id
        )
    }

    /// Spaces requests at least `interval` apart to respect the MusicBrainz
    /// rate limit. Each caller reserves its slot before sleeping, so one that
    /// enters the actor while another sleeps queues behind it instead of
    /// reading the same last request time and going out at once.
    private func throttle() async {
        let now = ContinuousClock.now
        let slot = lastRequestAt.map { max(now, $0 + interval) } ?? now
        lastRequestAt = slot
        try? await Task.sleep(until: slot, clock: .continuous)
    }

    /// Wraps a value as a Lucene phrase, escaping the only characters that are
    /// special inside quotes.
    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private struct SearchResult: Decodable {
        let releases: [Release]

        struct Release: Decodable {
            let id: String
            /// How well the release matches the query, 0–100.
            let score: Int?
            let releaseGroup: ReleaseGroup?

            enum CodingKeys: String, CodingKey {
                case id
                case score
                case releaseGroup = "release-group"
            }
        }

        struct ReleaseGroup: Decodable {
            let id: String
        }
    }
}
