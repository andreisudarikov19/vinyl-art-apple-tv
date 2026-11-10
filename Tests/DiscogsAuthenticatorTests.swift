import Foundation
import os
import Security
import Testing
@testable import VinylForAppleTV

/// Each test keeps its sign-in under a keychain service of its own, removed
/// afterwards, so the app's stored sign-in is never touched.
@MainActor
@Suite(.serialized)
final class DiscogsAuthenticatorTests {
    private typealias Responder = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let store = DiscogsCredentialsStore(service: "com.andreisudarikov.VinylForAppleTV.tests.\(UUID().uuidString)")
    private let signedIn = DiscogsCredentials(username: "tester", accessToken: "access", accessTokenSecret: "accessSecret")

    deinit {
        try? store.clear()
    }

    private func makeAuthenticator(
        consumer: OAuth1.Credentials? = OAuth1.Credentials(consumerKey: "consumer", consumerSecret: "consumerSecret")
    ) -> DiscogsAuthenticator {
        DiscogsAuthenticator(urlSession: StubSession.make(), consumerCredentials: consumer, credentialsStore: store)
    }

    private nonisolated static func text(_ body: String, status: Int = 200) -> Responder {
        { request in (stubHTTPResponse(for: request, statusCode: status), Data(body.utf8)) }
    }

    private nonisolated static let requestToken = text("oauth_token=request&oauth_token_secret=requestSecret&oauth_callback_confirmed=true")
    private nonisolated static let accessToken = text("oauth_token=access&oauth_token_secret=accessSecret")
    private nonisolated static let identity = text(#"{"id": 1, "username": "tester", "resource_url": "https://api.discogs.com/users/tester"}"#)

    /// Routes stubbed requests by OAuth endpoint, each answering as Discogs
    /// does after a good sign-in unless replaced.
    private func stub(
        requestToken: @escaping Responder = DiscogsAuthenticatorTests.requestToken,
        accessToken: @escaping Responder = DiscogsAuthenticatorTests.accessToken,
        identity: @escaping Responder = DiscogsAuthenticatorTests.identity
    ) {
        StubURLProtocol.responder = { request in
            switch request.url?.path {
            case "/oauth/request_token": return try requestToken(request)
            case "/oauth/access_token": return try accessToken(request)
            default: return try identity(request)
            }
        }
    }

    @Test func requestTokenLeadsToTheAuthorizePage() async {
        stub()
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()

        let authorizeURL = URL(string: "https://www.discogs.com/oauth/authorize?oauth_token=request")!
        #expect(authenticator.state == .awaitingVerifier(authorizeURL: authorizeURL))
    }

    @Test func malformedRequestTokenFails() async {
        stub(requestToken: Self.text("oauth_token=request"))
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()

        #expect(authenticator.state == .failed(message: DiscogsAuthError.invalidServerResponse.localizedDescription))
    }

    @Test func serverErrorNamesTheStatus() async {
        stub(requestToken: Self.text("Internal Server Error", status: 500))
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()

        #expect(authenticator.state == .failed(message: "Discogs error (HTTP 500)."))
    }

    @Test func verifierIsSentWithoutSurroundingWhitespace() async {
        let verifiers = OSAllocatedUnfairLock(initialState: [String?]())
        stub(accessToken: { request in
            verifiers.withLock { $0.append(authorizationParameters(request)["oauth_verifier"]) }
            return try Self.accessToken(request)
        })
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()
        await authenticator.submitVerifier("  CODE \n")

        #expect(verifiers.withLock { $0 } == ["CODE"])
    }

    @Test func verifiedSignInIsAuthenticatedAndStored() async throws {
        stub()
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()
        await authenticator.submitVerifier("CODE")

        #expect(authenticator.state == .authenticated(signedIn))
        #expect(try store.load() == signedIn)
    }

    @Test func failedIdentityFetchFailsWithoutStoring() async throws {
        stub(identity: Self.text("Service Unavailable", status: 503))
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()
        await authenticator.submitVerifier("CODE")

        #expect(authenticator.state == .failed(message: "Discogs error (HTTP 503)."))
        #expect(try store.load() == nil)
    }

    @Test func verifierWithoutAPendingSignInFails() async {
        let requests = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { request in
            requests.withLock { $0 += 1 }
            return try Self.requestToken(request)
        }
        let authenticator = makeAuthenticator()

        await authenticator.submitVerifier("CODE")

        #expect(authenticator.state == .failed(message: DiscogsAuthError.noPendingAuthorization.localizedDescription))
        #expect(requests.withLock { $0 } == 0)
    }

    @Test func missingConsumerKeysFailWithoutARequest() async {
        let requests = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { request in
            requests.withLock { $0 += 1 }
            return try Self.requestToken(request)
        }
        let authenticator = makeAuthenticator(consumer: nil)

        await authenticator.startAuthorization()

        #expect(authenticator.state == .failed(message: DiscogsAuthError.missingCredentials.localizedDescription))
        #expect(requests.withLock { $0 } == 0)
    }

    @Test func bootstrapRestoresAStoredSignIn() async throws {
        try store.save(signedIn)
        let authenticator = makeAuthenticator()

        await authenticator.bootstrap()

        #expect(authenticator.state == .authenticated(signedIn))
    }

    @Test func bootstrapWithoutAStoredSignInIsIdle() async {
        let authenticator = makeAuthenticator()

        await authenticator.bootstrap()

        #expect(authenticator.state == .idle)
    }

    @Test func bootstrapCarriesOverASignInSyncedByAnEarlierBuild() async throws {
        try store.saveSynced(signedIn)
        let authenticator = makeAuthenticator()

        await authenticator.bootstrap()

        #expect(authenticator.state == .authenticated(signedIn))
        #expect(try store.storedItems() == [.thisDeviceOnly])
    }

    @Test func signOutForgetsTheStoredSignIn() async throws {
        try store.save(signedIn)
        let authenticator = makeAuthenticator()
        await authenticator.bootstrap()

        await authenticator.signOut()

        #expect(authenticator.state == .idle)
        #expect(try store.load() == nil)
    }

    @Test func signOutForgetsASyncedCopyToo() async throws {
        try store.save(signedIn)
        try store.saveSynced(signedIn)
        let authenticator = makeAuthenticator()
        await authenticator.bootstrap()

        await authenticator.signOut()

        #expect(try store.storedItems().isEmpty)
    }

    @Test func expiredSignInSignsOutWithANoticeUntilTheNextSignIn() async throws {
        try store.save(signedIn)
        stub()
        let authenticator = makeAuthenticator()
        await authenticator.bootstrap()

        await authenticator.signInExpired()

        #expect(authenticator.state == .idle)
        #expect(authenticator.notice != nil)
        #expect(try store.load() == nil)

        await authenticator.startAuthorization()

        #expect(authenticator.notice == nil)
    }

    @Test func expiredSignInIsIgnoredDuringANewSignIn() async {
        stub()
        let authenticator = makeAuthenticator()
        await authenticator.startAuthorization()
        let awaiting = authenticator.state

        await authenticator.signInExpired()

        #expect(authenticator.state == awaiting)
        #expect(authenticator.notice == nil)
    }

    @Test func rejectedVerificationCodeSaysHowToRecover() async {
        stub(accessToken: Self.text("Invalid verifier.", status: 401))
        let authenticator = makeAuthenticator()

        await authenticator.startAuthorization()
        await authenticator.submitVerifier("WRONG")

        #expect(authenticator.state == .failed(message: DiscogsAuthError.verifierRejected.localizedDescription))
    }
}

/// Each test keeps its sign-in under a keychain service of its own and its
/// launch marker in a defaults suite of its own, both removed afterwards.
final class DiscogsCredentialsStoreTests {
    private let store = DiscogsCredentialsStore(service: "com.andreisudarikov.VinylForAppleTV.tests.\(UUID().uuidString)")
    private let suiteName = "com.andreisudarikov.VinylForAppleTV.tests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let signedIn = DiscogsCredentials(username: "tester", accessToken: "access", accessTokenSecret: "accessSecret")

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        store.removeEveryItem()
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func signInIsSavedOnThisDeviceOnly() throws {
        try store.save(signedIn)

        #expect(try store.storedItems() == [.thisDeviceOnly])
        #expect(try store.load() == signedIn)
    }

    @Test func syncedSignInIsCarriedOverToThisDeviceOnly() throws {
        try store.saveSynced(signedIn)

        #expect(try store.load() == signedIn)
        #expect(try store.storedItems() == [.thisDeviceOnly])
        #expect(try store.load() == signedIn)
    }

    @Test func freshInstallRemovesASignInLeftByAnEarlierInstall() throws {
        try store.save(signedIn)
        try store.saveSynced(signedIn)

        try store.removeSignInLeftByAnEarlierInstall(defaults: defaults, appDataExists: false)

        #expect(try store.storedItems().isEmpty)
    }

    @Test func updateFromABuildWithoutTheMarkerKeepsTheSignIn() throws {
        try store.saveSynced(signedIn)

        try store.removeSignInLeftByAnEarlierInstall(defaults: defaults, appDataExists: true)

        #expect(try store.load() == signedIn)
    }

    /// The app's data on tvOS lives in Caches, which the system may empty
    /// between launches; only the first launch of an install may remove.
    @Test func laterLaunchesKeepTheSignIn() throws {
        try store.removeSignInLeftByAnEarlierInstall(defaults: defaults, appDataExists: false)
        try store.save(signedIn)

        try store.removeSignInLeftByAnEarlierInstall(defaults: defaults, appDataExists: false)
        try store.removeSignInLeftByAnEarlierInstall(defaults: defaults, appDataExists: true)

        #expect(try store.load() == signedIn)
    }
}

/// One keychain item under a test's service, as `storedItems()` reads it.
fileprivate struct StoredKeychainItem: Equatable {
    let synced: Bool
    let accessible: String?

    static let thisDeviceOnly = StoredKeychainItem(
        synced: false,
        accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
}

/// Reaches the keychain directly, so tests can set up a sign-in as builds up
/// to 0.20.0 saved it and check what's stored without going through the
/// code under test.
fileprivate extension DiscogsCredentialsStore {
    /// Saves `credentials` synced through iCloud Keychain, as 0.20.0 did.
    func saveSynced(_ credentials: DiscogsCredentials) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "oauth-credentials",
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: try JSONEncoder().encode(credentials),
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Every item under the service, synced or not.
    func storedItems() throws -> [StoredKeychainItem] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw KeychainError.unexpectedStatus(status)
        }
        return items.map { item in
            StoredKeychainItem(
                synced: item[kSecAttrSynchronizable as String] as? Bool ?? false,
                accessible: item[kSecAttrAccessible as String] as? String
            )
        }
    }

    func removeEveryItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
