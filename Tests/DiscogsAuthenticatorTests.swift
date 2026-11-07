import Foundation
import os
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

    @Test func signOutForgetsTheStoredSignIn() async throws {
        try store.save(signedIn)
        let authenticator = makeAuthenticator()
        await authenticator.bootstrap()

        await authenticator.signOut()

        #expect(authenticator.state == .idle)
        #expect(try store.load() == nil)
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
