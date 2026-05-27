import Foundation

struct DiscogsCredentials: Codable, Sendable, Equatable {
    let username: String
    let accessToken: String
    let accessTokenSecret: String

    var oauthToken: OAuth1.Token {
        OAuth1.Token(token: accessToken, tokenSecret: accessTokenSecret)
    }
}

enum DiscogsCredentialsStore {
    private static let service = "com.andreisudarikov.VinylForAppleTV.discogs"
    private static let account = "oauth-credentials"

    static func save(_ credentials: DiscogsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try KeychainStore.save(data, account: account, service: service)
    }

    static func load() throws -> DiscogsCredentials? {
        guard let data = try KeychainStore.load(account: account, service: service) else {
            return nil
        }
        return try JSONDecoder().decode(DiscogsCredentials.self, from: data)
    }

    static func clear() throws {
        try KeychainStore.remove(account: account, service: service)
    }
}
