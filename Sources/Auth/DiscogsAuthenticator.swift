import Foundation
import Observation

enum DiscogsAuthError: Error, LocalizedError, Sendable {
    case missingCredentials
    case invalidServerResponse
    case serverError(status: Int, body: String)
    case verifierRejected
    case noPendingAuthorization
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Discogs consumer key and secret are not configured. Update AppSecrets.swift."
        case .invalidServerResponse:
            return "Discogs returned an unexpected response."
        case .serverError(let status, _):
            return "Discogs error (HTTP \(status))."
        case .verifierRejected:
            return "Discogs didn't accept that code. It may be mistyped or expired. Choose Try again to get a fresh one."
        case .noPendingAuthorization:
            return "No pending authorization. Start sign-in again."
        case .keychainFailure(let status):
            return "Keychain error (\(status))."
        }
    }
}

@MainActor
@Observable
final class DiscogsAuthenticator {
    enum State: Sendable, Equatable {
        case loading
        case idle
        case requestingToken
        case awaitingVerifier(authorizeURL: URL)
        case exchangingToken
        case authenticated(DiscogsCredentials)
        case failed(message: String)
    }

    private(set) var state: State = .loading

    /// Why the user is back at the welcome screen, shown there until the
    /// next sign-in starts. Set when Discogs stops accepting the stored token.
    private(set) var notice: String?

    private var pendingRequestToken: OAuth1.Token?
    private let urlSession: URLSession
    private let consumerCredentials: OAuth1.Credentials?
    private let credentialsStore: DiscogsCredentialsStore

    /// - Parameters:
    ///   - consumerCredentials: The app's Discogs consumer key and secret,
    ///     nil when they aren't configured.
    ///   - credentialsStore: Where the sign-in is kept.
    init(
        urlSession: URLSession = .shared,
        consumerCredentials: OAuth1.Credentials? = DiscogsAuthenticator.appConsumerCredentials,
        credentialsStore: DiscogsCredentialsStore = .standard
    ) {
        self.urlSession = urlSession
        self.consumerCredentials = consumerCredentials
        self.credentialsStore = credentialsStore
    }

    /// The consumer key and secret from AppSecrets.swift, or nil while it
    /// still has the template's placeholders.
    static var appConsumerCredentials: OAuth1.Credentials? {
        guard AppSecrets.hasDiscogsCredentials else { return nil }
        return OAuth1.Credentials(
            consumerKey: AppSecrets.discogsConsumerKey,
            consumerSecret: AppSecrets.discogsConsumerSecret
        )
    }

    func bootstrap() async {
        do {
            if let credentials = try credentialsStore.load() {
                state = .authenticated(credentials)
            } else {
                state = .idle
            }
        } catch {
            state = .idle
        }
    }

    func startAuthorization() async {
        guard let consumerCredentials else {
            state = .failed(message: DiscogsAuthError.missingCredentials.localizedDescription)
            return
        }
        notice = nil
        state = .requestingToken
        do {
            let token = try await requestRequestToken(consumer: consumerCredentials)
            pendingRequestToken = token
            let authorizeURL = URL(
                string: "https://www.discogs.com/oauth/authorize?oauth_token=\(token.token)"
            )!
            state = .awaitingVerifier(authorizeURL: authorizeURL)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func submitVerifier(_ rawVerifier: String) async {
        let verifier = rawVerifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestToken = pendingRequestToken, let consumerCredentials else {
            state = .failed(message: DiscogsAuthError.noPendingAuthorization.localizedDescription)
            return
        }
        state = .exchangingToken
        do {
            let accessToken = try await exchangeAccessToken(
                consumer: consumerCredentials,
                verifier: verifier,
                requestToken: requestToken
            )
            let username = try await fetchUsername(consumer: consumerCredentials, accessToken: accessToken)
            let credentials = DiscogsCredentials(
                username: username,
                accessToken: accessToken.token,
                accessTokenSecret: accessToken.tokenSecret
            )
            try credentialsStore.save(credentials)
            pendingRequestToken = nil
            state = .authenticated(credentials)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func signOut() async {
        try? credentialsStore.clear()
        pendingRequestToken = nil
        state = .idle
    }

    /// Drops a sign-in Discogs no longer accepts (revoked or expired) and
    /// returns to the welcome screen with a notice. The cached library stays,
    /// so signing back in as the same account shows it at once. Ignored
    /// unless signed in, so a late 401 can't cut into a new sign-in.
    func signInExpired() async {
        guard case .authenticated = state else { return }
        notice = "Discogs no longer accepts this app's access. Sign in again to pick up where you left off."
        await signOut()
    }

    // MARK: - Network

    private func requestRequestToken(consumer: OAuth1.Credentials) async throws -> OAuth1.Token {
        let url = URL(string: "https://api.discogs.com/oauth/request_token")!
        let request = OAuth1.signedRequest(
            method: "GET",
            url: url,
            credentials: consumer,
            token: .none,
            extraOAuthParameters: ["oauth_callback": "oob"],
            additionalHeaders: ["User-Agent": UserAgent.app]
        )
        let body = try await performText(request)
        guard let token = body["oauth_token"], let secret = body["oauth_token_secret"] else {
            throw DiscogsAuthError.invalidServerResponse
        }
        return OAuth1.Token(token: token, tokenSecret: secret)
    }

    private func exchangeAccessToken(
        consumer: OAuth1.Credentials,
        verifier: String,
        requestToken: OAuth1.Token
    ) async throws -> OAuth1.Token {
        let url = URL(string: "https://api.discogs.com/oauth/access_token")!
        let request = OAuth1.signedRequest(
            method: "POST",
            url: url,
            credentials: consumer,
            token: requestToken,
            extraOAuthParameters: ["oauth_verifier": verifier],
            additionalHeaders: ["User-Agent": UserAgent.app]
        )
        let body: [String: String]
        do {
            body = try await performText(request)
        } catch DiscogsAuthError.serverError(status: 401, _) {
            // A mistyped code, or one whose request token has expired.
            throw DiscogsAuthError.verifierRejected
        }
        guard let token = body["oauth_token"], let secret = body["oauth_token_secret"] else {
            throw DiscogsAuthError.invalidServerResponse
        }
        return OAuth1.Token(token: token, tokenSecret: secret)
    }

    private func fetchUsername(consumer: OAuth1.Credentials, accessToken: OAuth1.Token) async throws -> String {
        let url = URL(string: "https://api.discogs.com/oauth/identity")!
        let request = OAuth1.signedRequest(
            method: "GET",
            url: url,
            credentials: consumer,
            token: accessToken,
            additionalHeaders: ["User-Agent": UserAgent.app]
        )
        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response: response, data: data)
        let identity = try JSONDecoder().decode(IdentityResponse.self, from: data)
        return identity.username
    }

    private struct IdentityResponse: Decodable {
        let username: String
    }

    private func performText(_ request: URLRequest) async throws -> [String: String] {
        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response: response, data: data)
        let bodyString = String(decoding: data, as: UTF8.self)
        return Self.parseFormEncoded(bodyString)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw DiscogsAuthError.invalidServerResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DiscogsAuthError.serverError(status: http.statusCode, body: body)
        }
    }

    private static func parseFormEncoded(_ string: String) -> [String: String] {
        var components = URLComponents()
        components.query = string
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value {
                result[item.name] = value
            }
        }
        return result
    }
}
