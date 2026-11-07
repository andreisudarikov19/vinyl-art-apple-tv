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

    private static let releaseDetail = Data(#"{"id": 7, "title": "Album", "tracklist": []}"#.utf8)

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

    @Test func timedOutReleaseSucceedsAfterOneRetry() async throws {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { request in
            let attempt = attempts.withLock { $0 += 1; return $0 }
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            return (stubHTTPResponse(for: request), Self.releaseDetail)
        }

        let detail = try await makeClient().release(id: 7)

        #expect(detail.id == 7)
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test func secondTimeoutThrows() async {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        StubURLProtocol.responder = { _ in
            attempts.withLock { $0 += 1 }
            throw URLError(.timedOut)
        }

        let error = await #expect(throws: URLError.self) {
            try await makeClient().release(id: 7)
        }
        #expect(error?.code == .timedOut)
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test func requestAfterFiveOrFewerRemainingWaitsASecond() async throws {
        StubURLProtocol.responder = { request in
            (stubHTTPResponse(for: request, rateLimitRemaining: 5), Self.releaseDetail)
        }
        let waits = OSAllocatedUnfairLock(initialState: [Duration]())
        let client = makeClient(waits: waits)

        _ = try await client.release(id: 7)
        #expect(waits.withLock { $0 }.isEmpty)
        _ = try await client.release(id: 7)

        #expect(waits.withLock { $0 } == [.seconds(1)])
    }

    @Test func requestAfterMoreThanFiveRemainingDoesNotWait() async throws {
        StubURLProtocol.responder = { request in
            (stubHTTPResponse(for: request, rateLimitRemaining: 6), Self.releaseDetail)
        }
        let waits = OSAllocatedUnfairLock(initialState: [Duration]())
        let client = makeClient(waits: waits)

        _ = try await client.release(id: 7)
        _ = try await client.release(id: 7)

        #expect(waits.withLock { $0 }.isEmpty)
    }
}
