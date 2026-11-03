import Foundation
import Testing
@testable import VinylForAppleTV

/// Needs real consumer keys in AppSecrets.swift: without them sign-in stops
/// before any request is made.
@MainActor
@Suite(.serialized, .enabled(if: AppSecrets.hasDiscogsCredentials))
struct DiscogsAuthenticatorTests {
    @Test func rejectedVerificationCodeSaysHowToRecover() async {
        StubURLProtocol.responder = { request in
            if request.url?.path == "/oauth/request_token" {
                let body = "oauth_token=request&oauth_token_secret=secret&oauth_callback_confirmed=true"
                return (stubHTTPResponse(for: request), Data(body.utf8))
            }
            return (stubHTTPResponse(for: request, statusCode: 401), Data("Invalid verifier.".utf8))
        }
        let authenticator = DiscogsAuthenticator(urlSession: StubSession.make())

        await authenticator.startAuthorization()
        await authenticator.submitVerifier("WRONG")

        #expect(authenticator.state == .failed(message: DiscogsAuthError.verifierRejected.localizedDescription))
    }
}
