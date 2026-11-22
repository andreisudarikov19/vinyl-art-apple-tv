import Foundation
import Testing
@testable import VinylForAppleTV

struct RecordFactsTests {
    @Test func writesTrackCountAndPlayingTime() {
        #expect(RecordFacts.length(durations: ["2:36", "2:05"]) == "2 tracks · 5 min")
        #expect(RecordFacts.length(durations: ["1:00:00", "52:00"]) == "2 tracks · 1 h 52 min")
        #expect(RecordFacts.length(durations: ["4:04"]) == "1 track · 4 min")
    }

    @Test func leavesTheTimeOutWhenADurationIsMissing() {
        #expect(RecordFacts.length(durations: ["3:00", ""]) == "2 tracks")
        #expect(RecordFacts.length(durations: ["3:00", "abc"]) == "2 tracks")
        #expect(RecordFacts.length(durations: []) == nil)
    }

    @Test func formatsPlayingTime() {
        #expect(RecordFacts.playingTime(seconds: 6720) == "1 h 52 min")
        #expect(RecordFacts.playingTime(seconds: 7200) == "2 h")
        #expect(RecordFacts.playingTime(seconds: 2220) == "37 min")
        #expect(RecordFacts.playingTime(seconds: 20) == "1 min")
    }

    @Test func writesThePublishedRow() {
        #expect(RecordFacts.published(year: 1976, country: "Netherlands") == "1976 · Netherlands")
        #expect(RecordFacts.published(year: 1976, country: nil) == "1976")
        #expect(RecordFacts.published(year: 1976, country: "  ") == "1976")
        #expect(RecordFacts.published(year: 0, country: "Netherlands") == "Netherlands")
        #expect(RecordFacts.published(year: 0, country: nil) == nil)
    }
}
