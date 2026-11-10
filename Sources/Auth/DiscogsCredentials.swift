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

    /// Builds up to 0.20.0 saved the sign-in synced through iCloud Keychain.
    /// Finding only that copy, this keeps it on this device instead and
    /// removes the synced one, so updating the app stays signed in.
    func load() throws -> DiscogsCredentials? {
        if let data = try KeychainStore.load(account: account, service: service) {
            return try JSONDecoder().decode(DiscogsCredentials.self, from: data)
        }
        guard let synced = try KeychainStore.load(account: account, service: service, kind: .synced) else {
            return nil
        }
        let credentials = try JSONDecoder().decode(DiscogsCredentials.self, from: synced)
        try KeychainStore.save(synced, account: account, service: service)
        try KeychainStore.remove(account: account, service: service, kind: .synced)
        return credentials
    }

    /// Removes the sign-in, synced or not.
    func clear() throws {
        try KeychainStore.remove(account: account, service: service)
    }

    /// Keychain items outlive uninstalling the app, so a reinstall would sign
    /// back in. Uninstalling does remove the app's data, `defaults` included,
    /// so the first launch after a fresh install finds no marker there and
    /// removes any sign-in an earlier install left. Builds up to 0.20.0 set
    /// no marker but left app data, which `appDataExists` reports, so an
    /// update from one keeps the sign-in. Call it before this launch writes
    /// any app data.
    func removeSignInLeftByAnEarlierInstall(defaults: UserDefaults, appDataExists: Bool) throws {
        guard !defaults.bool(forKey: Self.leftoverSignInCheckedKey) else { return }
        if !appDataExists {
            try clear()
        }
        defaults.set(true, forKey: Self.leftoverSignInCheckedKey)
    }

    /// Set once an install has checked for a sign-in left by an earlier one.
    static let leftoverSignInCheckedKey = "leftoverSignInChecked"
}
