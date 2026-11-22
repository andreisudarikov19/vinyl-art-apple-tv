import Foundation
import os
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct MusicBrainzClientTests {
    private func search(returning releases: [(id: String, score: Int?)]) async throws -> MusicBrainzMatch? {
        StubURLProtocol.responder = { request in
            (stubHTTPResponse(for: request), musicBrainzSearchJSON(releases: releases))
        }
        let client = MusicBrainzClient(session: StubSession.make(), interval: .zero)
        return try await client.bestMatch(artist: "Artist", title: "Title", catalogNumber: nil)
    }

    @Test func readsTheYearOfAMusicBrainzDate() {
        #expect(MusicBrainzClient.year(from: "1959") == 1959)
        #expect(MusicBrainzClient.year(from: "1959-08-17") == 1959)
        #expect(MusicBrainzClient.year(from: "") == nil)
        #expect(MusicBrainzClient.year(from: "0000") == nil)
        #expect(MusicBrainzClient.year(from: nil) == nil)
    }

    @Test func earliestYearIsTakenFromTheMatchesNotTheBestScore() {
        // A reissue, a later reissue and an undated match: the original year wins.
        #expect(MusicBrainzClient.earliestYear(from: ["2014-11-24", "1988-07-01", "1964", nil]) == 1964)
        #expect(MusicBrainzClient.earliestYear(from: [nil, "garbage"]) == nil)
        #expect(MusicBrainzClient.earliestYear(from: []) == nil)
    }

    @Test func resultsScoringBelowNinetyAreNoMatch() async throws {
        let match = try await search(returning: [("close", 89), ("unscored", nil)])

        #expect(match == nil)
    }

    @Test func highestScoringResultWins() async throws {
        let match = try await search(returning: [("good", 92), ("best", 100), ("better", 95)])

        #expect(match?.releaseMBID == "best")
        #expect(match?.releaseGroupMBID == "best-group")
    }

    @Test func concurrentLookupsGoOutOneIntervalApart() async throws {
        let requestTimes = OSAllocatedUnfairLock(initialState: [ContinuousClock.Instant]())
        StubURLProtocol.responder = { request in
            requestTimes.withLock { $0.append(.now) }
            return (stubHTTPResponse(for: request), musicBrainzSearchJSON(releases: []))
        }
        let interval = Duration.milliseconds(300)
        let client = MusicBrainzClient(session: StubSession.make(), interval: interval)

        // The first lookup sets the last request time; the next two arrive
        // together and must still queue one behind the other.
        _ = try await client.bestMatch(artist: "Artist", title: "First", catalogNumber: nil)
        async let second = client.bestMatch(artist: "Artist", title: "Second", catalogNumber: nil)
        async let third = client.bestMatch(artist: "Artist", title: "Third", catalogNumber: nil)
        _ = try await (second, third)

        let times = requestTimes.withLock { $0 }.sorted()
        #expect(times.count == 3)
        for (earlier, later) in zip(times, times.dropFirst()) {
            // A little slack for URL loading delivering a request after its slot.
            #expect(later - earlier >= interval - .milliseconds(50))
        }
    }
}
