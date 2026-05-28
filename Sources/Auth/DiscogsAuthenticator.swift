import Foundation
import Observation

enum DiscogsAuthError: Error, LocalizedError, Sendable {
    case missingCredentials
    case invalidServerResponse
    case serverError(status: Int, body: String)
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

    private var pendingRequestToken: OAuth1.Token?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func bootstrap() async {
        do {
            if let credentials = try DiscogsCredentialsStore.load() {
                state = .authenticated(credentials)
            } else {
                state = .idle
            }
        } catch {
            state = .idle
        }
    }

    func startAuthorization() async {
        guard AppSecrets.hasDiscogsCredentials else {
            state = .failed(message: DiscogsAuthError.missingCredentials.localizedDescription)
            return
        }
        state = .requestingToken
        do {
            let token = try await requestRequestToken()
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
        guard let requestToken = pendingRequestToken else {
            state = .failed(message: DiscogsAuthError.noPendingAuthorization.localizedDescription)
            return
        }
        state = .exchangingToken
        do {
            let accessToken = try await exchangeAccessToken(verifier: verifier, requestToken: requestToken)
            let username = try await fetchUsername(accessToken: accessToken)
            let credentials = DiscogsCredentials(
                username: username,
                accessToken: accessToken.token,
                accessTokenSecret: accessToken.tokenSecret
            )
            try DiscogsCredentialsStore.save(credentials)
            pendingRequestToken = nil
            state = .authenticated(credentials)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func signOut() async {
        try? DiscogsCredentialsStore.clear()
        pendingRequestToken = nil
        state = .idle
    }

    func reset() {
        pendingRequestToken = nil
        state = .idle
    }

    // MARK: - Network

    private func requestRequestToken() async throws -> OAuth1.Token {
        let url = URL(string: "https://api.discogs.com/oauth/request_token")!
        let request = OAuth1.signedRequest(
            method: "GET",
            url: url,
            credentials: oauthCredentials,
            token: .none,
            extraOAuthParameters: ["oauth_callback": "oob"],
            additionalHeaders: ["User-Agent": AppSecrets.userAgent]
        )
        let body = try await performText(request)
        guard let token = body["oauth_token"], let secret = body["oauth_token_secret"] else {
            throw DiscogsAuthError.invalidServerResponse
        }
        return OAuth1.Token(token: token, tokenSecret: secret)
    }

    private func exchangeAccessToken(verifier: String, requestToken: OAuth1.Token) async throws -> OAuth1.Token {
        let url = URL(string: "https://api.discogs.com/oauth/access_token")!
        let request = OAuth1.signedRequest(
            method: "POST",
            url: url,
            credentials: oauthCredentials,
            token: requestToken,
            extraOAuthParameters: ["oauth_verifier": verifier],
            additionalHeaders: ["User-Agent": AppSecrets.userAgent]
        )
        let body = try await performText(request)
        guard let token = body["oauth_token"], let secret = body["oauth_token_secret"] else {
            throw DiscogsAuthError.invalidServerResponse
        }
        return OAuth1.Token(token: token, tokenSecret: secret)
    }

    private func fetchUsername(accessToken: OAuth1.Token) async throws -> String {
        let url = URL(string: "https://api.discogs.com/oauth/identity")!
        let request = OAuth1.signedRequest(
            method: "GET",
            url: url,
            credentials: oauthCredentials,
            token: accessToken,
            additionalHeaders: ["User-Agent": AppSecrets.userAgent]
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

    private var oauthCredentials: OAuth1.Credentials {
        OAuth1.Credentials(
            consumerKey: AppSecrets.discogsConsumerKey,
            consumerSecret: AppSecrets.discogsConsumerSecret
        )
    }
}
