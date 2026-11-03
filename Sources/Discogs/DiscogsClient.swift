import Foundation

enum DiscogsClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case decodingFailed
    case unauthorized
    case httpError(status: Int, body: String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Discogs returned an unexpected response."
        case .decodingFailed:
            return "Couldn't read the data Discogs returned."
        case .unauthorized:
            return "Discogs no longer accepts this app's access. Sign in again."
        case .httpError(let status, _):
            return "Discogs error (HTTP \(status))."
        case .rateLimited:
            return "Discogs rate limit reached. Try again in a moment."
        }
    }
}

actor DiscogsClient {
    enum Sort: String, Sendable {
        case added, artist, title, year
    }

    enum SortOrder: String, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    let username: String

    private let credentials: OAuth1.Credentials
    private let token: OAuth1.Token
    private let urlSession: URLSession
    private let onUnauthorized: (@Sendable () async -> Void)?
    private var rateLimitRemaining: Int?

    /// - Parameter onUnauthorized: Called when Discogs answers 401, before
    ///   the request throws `.unauthorized`, so one place can drop a revoked
    ///   sign-in for every caller.
    init(
        credentials: DiscogsCredentials,
        urlSession: URLSession = .shared,
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) {
        self.username = credentials.username
        self.credentials = OAuth1.Credentials(
            consumerKey: AppSecrets.discogsConsumerKey,
            consumerSecret: AppSecrets.discogsConsumerSecret
        )
        self.token = credentials.oauthToken
        self.urlSession = urlSession
        self.onUnauthorized = onUnauthorized
    }

    func collectionPage(
        page: Int,
        perPage: Int = 100,
        sort: Sort = .added,
        order: SortOrder = .descending
    ) async throws -> DiscogsCollectionPage {
        var components = URLComponents(
            string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases"
        )!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "sort_order", value: order.rawValue),
        ]
        return try await get(url: components.url!)
    }

    /// Full release including tracklist. Fetched lazily when a record opens,
    /// not during initial library build. Retries once on timeout —
    /// /releases/{id} returns the entire tracklist + metadata + credits in a
    /// single payload that can run to 100KB+ for box sets, and Discogs has
    /// been observed to occasionally take longer than `URLSession`'s default
    /// 60s on the first hit. A second attempt usually succeeds.
    func release(id: Int) async throws -> ReleaseDetail {
        let url = URL(string: "https://api.discogs.com/releases/\(id)")!
        do {
            return try await get(url: url)
        } catch let error as URLError where error.code == .timedOut {
            return try await get(url: url)
        }
    }

    private func get<T: Decodable & Sendable>(url: URL) async throws -> T {
        await throttleIfNeeded()
        let request = OAuth1.signedRequest(
            method: "GET",
            url: url,
            credentials: credentials,
            token: token,
            additionalHeaders: ["User-Agent": AppSecrets.userAgent]
        )
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DiscogsClientError.invalidResponse
        }
        if let remaining = http.value(forHTTPHeaderField: "X-Discogs-Ratelimit-Remaining"),
           let value = Int(remaining) {
            rateLimitRemaining = value
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                await onUnauthorized?()
                throw DiscogsClientError.unauthorized
            }
            if http.statusCode == 429 {
                throw DiscogsClientError.rateLimited
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DiscogsClientError.httpError(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DiscogsClientError.decodingFailed
        }
    }

    /// Discogs allows 60 authenticated requests/minute. When close to the
    /// ceiling, pace requests ~1s apart to avoid a 429.
    private func throttleIfNeeded() async {
        if let remaining = rateLimitRemaining, remaining <= 5 {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
