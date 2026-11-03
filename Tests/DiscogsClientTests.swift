import Foundation
import os
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct DiscogsClientTests {
    private func makeClient(
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) -> DiscogsClient {
        DiscogsClient(
            credentials: DiscogsCredentials(
                username: "tester",
                accessToken: "token",
                accessTokenSecret: "secret"
            ),
            urlSession: StubSession.make(),
            onUnauthorized: onUnauthorized
        )
    }

    @Test func unauthorizedThrowsAndCallsTheHook() async {
        StubURLProtocol.responder = { request in
            (stubHTTPResponse(for: request, statusCode: 401), Data())
        }
        let hookCalls = OSAllocatedUnfairLock(initialState: 0)
        let client = makeClient { hookCalls.withLock { $0 += 1 } }

        await #expect(throws: DiscogsClientError.unauthorized) {
            try await client.collectionPage(page: 1)
        }
        #expect(hookCalls.withLock { $0 } == 1)
    }
}
