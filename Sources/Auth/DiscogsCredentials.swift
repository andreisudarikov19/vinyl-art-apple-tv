import Foundation

struct DiscogsCredentials: Codable, Sendable, Equatable {
    let username: String
    let accessToken: String
    let accessTokenSecret: String

    var oauthToken: OAuth1.Token {
        OAuth1.Token(token: accessToken, tokenSecret: accessTokenSecret)
    }
}

/// Keeps the sign-in in the keychain under `service`. The app uses
/// `standard`; tests pass a throwaway service so they never touch it.
struct DiscogsCredentialsStore: Sendable {
    static let standard = DiscogsCredentialsStore(service: "com.andreisudarikov.VinylForAppleTV.discogs")

    let service: String
    private let account = "oauth-credentials"

    init(service: String) {
        self.service = service
    }

    func save(_ credentials: DiscogsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try KeychainStore.save(data, account: account, service: service)
    }

    func load() throws -> DiscogsCredentials? {
        guard let data = try KeychainStore.load(account: account, service: service) else {
            return nil
        }
        return try JSONDecoder().decode(DiscogsCredentials.self, from: data)
    }

    func clear() throws {
        try KeychainStore.remove(account: account, service: service)
    }
}
