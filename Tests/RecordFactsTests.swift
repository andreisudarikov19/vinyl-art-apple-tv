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

    @Test func buildsTheTableInOrder() {
        let rows = RecordFacts.rows(
            year: 1976,
            country: "Netherlands",
            genres: ["Rock"],
            styles: ["Surf", "Rock & Roll"],
            label: "EMI",
            durations: ["1:00:00", "52:00"],
            titleTakesTwoLines: false
        )
        #expect(rows.map(\.label) == ["PUBLISHED", "GENRE", "STYLE", "LABEL", "LENGTH"])
        #expect(rows[0].value == "1976 · Netherlands")
        #expect(rows[2].value == "Surf, Rock & Roll")
        #expect(rows[2].isQuiet)
        #expect(rows[2].lineLimit == 2)
        // The track count leads and the playing time follows, quieter.
        #expect(rows[4].value == "2 tracks")
        #expect(rows[4].tail == " · 1 h 52 min")
    }

    @Test func leavesOutRowsWithNothingToSay() {
        // Before the release has loaded: no country, no durations.
        let early = RecordFacts.rows(
            year: 1976, country: nil, genres: ["Rock"], styles: [], label: nil,
            durations: [], titleTakesTwoLines: false
        )
        #expect(early.map(\.label) == ["PUBLISHED", "GENRE"])
        #expect(early[0].value == "1976")
        // No year and no country: no PUBLISHED row. A blank label is no label.
        let bare = RecordFacts.rows(
            year: 0, country: nil, genres: [], styles: [], label: "  ",
            durations: ["3:00", ""], titleTakesTwoLines: false
        )
        #expect(bare.map(\.label) == ["LENGTH"])
        #expect(bare[0].value == "2 tracks")
        #expect(bare[0].tail == "")
    }

    @Test func holdsGenreAndStyleToOneLineUnderALongTitle() {
        #expect(RecordFacts.titleTakesTwoLines("Shadoogie") == false)
        #expect(RecordFacts.titleTakesTwoLines("Jazzaan Round Midnight (Dokument Van Het Zaanse Jazzleven Anno 1979)"))
        let rows = RecordFacts.rows(
            year: 1979, country: nil, genres: ["Jazz", "Pop"], styles: ["Big Band"], label: nil,
            durations: [], titleTakesTwoLines: true
        )
        #expect(rows.first { $0.label == "GENRE" }?.lineLimit == 1)
        #expect(rows.first { $0.label == "STYLE" }?.lineLimit == 1)
    }
}
