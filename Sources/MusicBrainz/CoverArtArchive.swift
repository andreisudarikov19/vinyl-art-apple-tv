import Foundation

/// Looks up front-cover art from the Cover Art Archive for a MusicBrainz
/// release or release group. Returns nil when there is no art: the JSON
/// listing endpoint answers 404, or lists no images. Throws when the archive
/// couldn't answer this time.
enum CoverArtArchive {
    static func frontCoverURL(
        forRelease mbid: String,
        session: URLSession = .shared
    ) async throws(CoverLookup.Failure) -> String? {
        try await frontCover(entity: "release", mbid: mbid, session: session)
    }

    static func frontCoverURL(
        forReleaseGroup mbid: String,
        session: URLSession = .shared
    ) async throws(CoverLookup.Failure) -> String? {
        try await frontCover(entity: "release-group", mbid: mbid, session: session)
    }

    private static func frontCover(
        entity: String,
        mbid: String,
        session: URLSession
    ) async throws(CoverLookup.Failure) -> String? {
        guard let url = URL(string: "https://coverartarchive.org/\(entity)/\(mbid)") else {
            return nil
        }

        guard let listing = try await CoverLookup.fetch(Listing.self, from: url, session: session) else {
            return nil
        }

        let image = listing.images.first(where: { $0.front }) ?? listing.images.first
        guard let chosen = image else { return nil }

        // Prefer the 1200px render for the full-screen cover view; fall back to
        // the original upload (always present) when no 1200 thumbnail exists.
        let raw = chosen.thumbnails.size1200 ?? chosen.image
        return httpsUpgraded(raw)
    }

    /// Cover Art Archive sometimes returns `http://` URLs; App Transport
    /// Security rejects those, so promote them to `https://`.
    private static func httpsUpgraded(_ urlString: String) -> String {
        guard urlString.hasPrefix("http://") else { return urlString }
        return "https://" + urlString.dropFirst("http://".count)
    }

    private struct Listing: Decodable {
        let images: [Image]

        struct Image: Decodable {
            let front: Bool
            let image: String
            let thumbnails: Thumbnails
        }

        struct Thumbnails: Decodable {
            let size1200: String?

            enum CodingKeys: String, CodingKey {
                case size1200 = "1200"
            }
        }
    }
}
