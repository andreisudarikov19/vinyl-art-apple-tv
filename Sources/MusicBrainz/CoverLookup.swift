import Foundation

/// The one request path for MusicBrainz and the Cover Art Archive. It sorts
/// each answer into one a retry won't change and one it might, so the cover
/// pipeline knows whether to give up on a release or try it again later.
enum CoverLookup {
    /// Why a lookup got no answer this time. Either is worth retrying.
    enum Failure: Error {
        /// The request didn't complete: offline, timed out or the connection
        /// dropped. Not the release's fault, so it isn't counted against it.
        case network
        /// HTTP 429 or 5xx. MusicBrainz answers 503 to a client over its rate
        /// limit.
        case unavailable
    }

    /// Returns the decoded body of a 200, or nil for any other answer a
    /// retry won't change: a 404 or other 4xx, or a body that doesn't decode.
    static func fetch<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        session: URLSession
    ) async throws(Failure) -> T? {
        var request = URLRequest(url: url)
        request.setValue(UserAgent.app, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network
        }

        guard let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200:
            return try? JSONDecoder().decode(T.self, from: data)
        case 429, 500...:
            throw .unavailable
        default:
            return nil
        }
    }
}
