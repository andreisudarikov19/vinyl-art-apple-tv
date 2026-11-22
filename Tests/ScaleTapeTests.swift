import Foundation
import Testing
@testable import VinylForAppleTV

struct ScaleTapeTests {
    /// 7 records from 1975, 2 from 1976, 8 from 1977, at the closest pitch,
    /// as on a long tape.
    private let tape = ScaleTape(
        groups: [String](repeating: "1975", count: 7) + ["1976", "1976"] + [String](repeating: "1977", count: 8),
        spacing: 16
    )

    @Test func readsTheGroupUnderTheNeedle() {
        #expect(tape.reading(at: 0) == "1975")
        #expect(tape.reading(at: 8) == "1976")
        #expect(tape.reading(at: 16) == "1977")
        #expect(tape.reading(at: 17) == nil)
    }

    @Test func findsWhereGroupsBegin() {
        #expect(tape.groupStarts == [0, 7, 9])
        #expect(tape.isGroupStart(7) && !tape.isGroupStart(8))
    }

    @Test func skipsALabelTooCloseToTheOneBefore() {
        // 1976 starts 7 ticks (112 pt) after 1975: kept. 1977 starts 2 ticks
        // (32 pt) after 1976: skipped.
        #expect(tape.labelledStarts == [0, 7])
    }

    @Test func placesTicksAtTheTapesSpacing() {
        #expect(tape.offset(of: 7, current: 7) == 0)
        #expect(tape.offset(of: 9, current: 7) == 32)
        #expect(tape.offset(of: 0, current: 7) == -112)
    }

    @Test func spreadsAShortTapeAndPacksALongOne() {
        // The box's 1200 pt shared out, held between 16 and 40 pt.
        #expect(ScaleTape.spacing(forCount: 0) == 16)
        #expect(ScaleTape.spacing(forCount: 30) == 40)
        #expect(ScaleTape.spacing(forCount: 60) == 20)
        #expect(ScaleTape.spacing(forCount: 75) == 16)
        #expect(ScaleTape.spacing(forCount: 612) == 16)
        // The same 17 records, spread: 1977 is now 2 ticks (80 pt) after
        // 1976, room enough for its label.
        let short = ScaleTape(groups: tape.groups)
        #expect(short.spacing == 40)
        #expect(short.labelledStarts == [0, 7, 9])
        #expect(short.tick(at: 9) == .labelledGroup)
        #expect(short.offset(of: 9, current: 7) == 80)
    }

    @Test func givesTheTallTickOnlyToAGroupWithALabel() {
        #expect(tape.tick(at: 0) == .labelledGroup)
        #expect(tape.tick(at: 1) == .record)
        #expect(tape.tick(at: 7) == .labelledGroup)
        // 1977 begins a group, but its label was skipped.
        #expect(tape.tick(at: 9) == .group)
    }

    @Test func fadesALabelAsItNearsTheReading() {
        // From record 0, 1976 is 112 pt right: 32 pt clear of the reading's
        // 80 pt, two thirds of the 48 pt fade.
        let near = tape.labels(current: 0).first?.opacity ?? 0
        #expect(abs(near - 32.0 / 48.0) < 1e-9)
        // From record 16, 1975 is 256 pt left, 80 pt clear: full strength.
        #expect(tape.labels(current: 16).first?.opacity == 1)
    }

    @Test func showsTheNeedlesOwnGroupOnlyFromAfar() {
        let long = ScaleTape(groups: [String](repeating: "A", count: 50) + [String](repeating: "B", count: 50))
        // A's label repeats the reading. 12 ticks (192 pt) away it is hidden;
        // 14 ticks (224 pt) away it is half faded in; 20 ticks away it is whole.
        #expect(long.labels(current: 12).map(\.text) == [])
        #expect(abs((long.labels(current: 14).first?.opacity ?? 0) - 0.5) < 1e-9)
        #expect(long.labels(current: 20).first?.opacity == 1)
    }

    @Test func hidesALabelUnderTheReading() {
        // With record 16 under the needle, 1975 is 256 pt to the left and
        // 1976 is 144 pt to the left, where its text would run under the
        // reading.
        #expect(tape.labels(current: 16).map(\.text) == ["1975"])
        // From record 0, 1975 is under the needle itself; 1976 is 112 pt right.
        #expect(tape.labels(current: 0).map(\.text) == ["1976"])
        #expect(tape.labels(current: 0).first?.offset == 112)
    }

    @Test func keepsALabelClearOfALongerOne() {
        // "Classical" is 135 pt wide, so the label after it waits until 151 pt
        // have passed. "Folk" starts 48 pt after it: skipped. "Latin" starts 208 pt after it: kept.
        let genres = ScaleTape(
            groups: [String](repeating: "Classical", count: 3)
                + [String](repeating: "Folk", count: 10)
                + [String](repeating: "Latin", count: 3)
                + [String](repeating: "Pop", count: 3),
            spacing: 16
        )
        #expect(genres.labelledStarts == [0, 13])
    }

    @Test func dropsLabelsOutsideTheBox() {
        let long = ScaleTape(groups: [String](repeating: "A", count: 50) + [String](repeating: "B", count: 50))
        #expect(long.labels(current: 0).isEmpty)          // B starts 800 pt away
        #expect(long.labels(current: 20).map(\.text) == ["A", "B"])
    }
}

struct ScaleGroupTests {
    @Test func namesYears() {
        #expect(ScaleGroup.year(1976) == "1976")
        #expect(ScaleGroup.year(0) == "Unknown")
    }

    @Test func namesLetters() {
        #expect(ScaleGroup.letter(for: "The Shadows") == "T")
        #expect(ScaleGroup.letter(for: "equinoxe") == "E")
        #expect(ScaleGroup.letter(for: "Émile") == "E")
        #expect(ScaleGroup.letter(for: "10cc") == "#")
        #expect(ScaleGroup.letter(for: "…And Justice") == "#")
        #expect(ScaleGroup.letter(for: "") == "#")
    }

    @Test func namesGenres() {
        #expect(ScaleGroup.genre("Rock") == "Rock")
        #expect(ScaleGroup.genre(nil) == "Unknown")
        #expect(ScaleGroup.genre("") == "Unknown")
    }
}
