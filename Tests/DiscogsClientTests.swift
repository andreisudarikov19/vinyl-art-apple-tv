import Foundation
import os
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct DiscogsClientTests {
    /// Waits are recorded in `waits` instead of slept, so retries are instant.
    private func makeClient(
        waits: OSAllocatedUnfairLock<[Duration]> = .init(initialState: []),
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) -> DiscogsClient {
        DiscogsClient(
            credentials: DiscogsCredentials(
                username: "tester",
                accessToken: "token",
                accessTokenSecret: "secret"
            ),
            urlSession: StubSession.make(),
            onUnauthorized: onUnauthorized,
            sleep: { duration in waits.withLock { $0.append(duration) } }
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

    @Test func rateLimitedRequestSucceedsAfterOneRetry() async throws {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { request in
            let attempt = attempts.withLock { $0 += 1; return $0 }
            if attempt == 1 {
                return (stubHTTPResponse(for: request, statusCode: 429), Data())
            }
            let data = collectionPageJSON(page: 1, pages: 1, items: 1, releases: [
                releaseJSON(id: 1, dateAdded: "2024-03-01T00:00:00-00:00"),
            ])
            return (stubHTTPResponse(for: request), data)
        }
        let waits = OSAllocatedUnfairLock(initialState: [Duration]())
        let client = makeClient(waits: waits)

        let page = try await client.collectionPage(page: 1)

        #expect(page.releases.map(\.id) == [1])
        #expect(attempts.withLock { $0 } == 2)
        #expect(waits.withLock { $0 } == Array(DiscogsClient.rateLimitBackoff.prefix(1)))
    }

    @Test func persistentRateLimitThrowsAfterBoundedRetries() async {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { request in
            attempts.withLock { $0 += 1 }
            return (stubHTTPResponse(for: request, statusCode: 429), Data())
        }
        let waits = OSAllocatedUnfairLock(initialState: [Duration]())
        let client = makeClient(waits: waits)

        await #expect(throws: DiscogsClientError.rateLimited) {
            try await client.collectionPage(page: 1)
        }
        #expect(attempts.withLock { $0 } == DiscogsClient.rateLimitBackoff.count + 1)
        #expect(waits.withLock { $0 } == DiscogsClient.rateLimitBackoff)
    }
}
