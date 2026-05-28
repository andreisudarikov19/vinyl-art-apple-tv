import Foundation

/// Looks up front-cover art from the Cover Art Archive for a MusicBrainz
/// release or release group. The JSON listing endpoint returns 404 when no art
/// exists, so a successful decode means there is a cover to show.
enum CoverArtArchive {
    static func frontCoverURL(forRelease mbid: String, session: URLSession = .shared) async -> String? {
        await frontCover(entity: "release", mbid: mbid, session: session)
    }

    static func frontCoverURL(forReleaseGroup mbid: String, session: URLSession = .shared) async -> String? {
        await frontCover(entity: "release-group", mbid: mbid, session: session)
    }

    private static func frontCover(entity: String, mbid: String, session: URLSession) async -> String? {
        guard let url = URL(string: "https://coverartarchive.org/\(entity)/\(mbid)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(AppSecrets.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let listing = try? JSONDecoder().decode(Listing.self, from: data)
        else { return nil }

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
