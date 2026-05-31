import Foundation
import Testing
@testable import VinylForAppleTV

private func makeReleaseDetail(tracklist: [[String: Any]]) throws -> ReleaseDetail {
    let object: [String: Any] = ["id": 1, "title": "Album", "tracklist": tracklist]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(ReleaseDetail.self, from: data)
}

private func track(_ position: String, _ title: String, duration: String = "3:00", type: String = "track", credits: [(name: String, role: String)] = []) -> [String: Any] {
    var entry: [String: Any] = ["position": position, "title": title, "duration": duration, "type_": type]
    if !credits.isEmpty {
        entry["extraartists"] = credits.map { ["name": $0.name, "role": $0.role] }
    }
    return entry
}

struct RecordSidesTests {
    @Test func groupsTracksIntoSidesInOrder() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "One"), track("A2", "Two"), track("B1", "Three"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.map(\.name) == ["Side A", "Side B"])
        #expect(sides[0].tracks.map(\.title) == ["One", "Two"])
        #expect(sides[1].tracks.map(\.title) == ["Three"])
    }

    @Test func multiDiscProducesFourSides() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "a"), track("B1", "b"), track("C1", "c"), track("D1", "d"),
        ])
        #expect(RecordSides.from(detail.tracklist).map(\.name) == ["Side A", "Side B", "Side C", "Side D"])
    }

    @Test func headingsAreExcluded() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("", "Act I", type: "heading"), track("A1", "One"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.count == 1)
        #expect(sides[0].tracks.map(\.title) == ["One"])
    }

    @Test func extractsComposedByCredits() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Spain", credits: [
                (name: "Chick Corea", role: "Composed By"),
                (name: "Joaquín Rodrigo", role: "Composed By"),
            ]),
            track("A2", "Crystal Silence"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        let credits = sides[0].tracks[0].credits
        #expect(credits.count == 1)
        #expect(credits[0].role == "Composed by")
        #expect(credits[0].names == ["Chick Corea", "Joaquín Rodrigo"])
        #expect(credits[0].displayLine == "Composed by Chick Corea, Joaquín Rodrigo")
        #expect(sides[0].tracks[1].credits.isEmpty)
    }

    @Test func extractsLeadAndBackingVocalsSeparately() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Song", credits: [
                (name: "Alice", role: "Lead Vocals"),
                (name: "Bob", role: "Backing Vocals"),
                (name: "Carol", role: "Backing Vocals"),
            ]),
        ])
        let credits = RecordSides.from(detail.tracklist)[0].tracks[0].credits
        #expect(credits.count == 2)
        #expect(credits[0].role == "Lead vocals by")
        #expect(credits[0].names == ["Alice"])
        #expect(credits[1].role == "Backing vocals by")
        #expect(credits[1].names == ["Bob", "Carol"])
    }

    @Test func bracketedBackingVocalsAlsoMaps() throws {
        // Discogs sometimes uses "Vocals [Backing]" instead of "Backing Vocals".
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Song", credits: [
                (name: "Alice", role: "Vocals [Backing]"),
            ]),
        ])
        let credits = RecordSides.from(detail.tracklist)[0].tracks[0].credits
        #expect(credits == [TrackCredit(role: "Backing vocals by", names: ["Alice"])])
    }

    @Test func filtersOutNonTracklistRoles() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Song", credits: [
                (name: "Producer Name", role: "Producer"),
                (name: "Engineer Name", role: "Engineer"),
                (name: "Mixer Name", role: "Mixed By"),
                (name: "Guitarist Name", role: "Guitar"),
                (name: "Singer Name", role: "Vocals"),
            ]),
        ])
        let credits = RecordSides.from(detail.tracklist)[0].tracks[0].credits
        #expect(credits == [TrackCredit(role: "Vocals by", names: ["Singer Name"])])
    }

    @Test func multipleCreditTypesPreserveDiscogsOrder() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Song", credits: [
                (name: "Diana Krall", role: "Vocals"),
                (name: "Cole Porter", role: "Composed By"),
                (name: "Cole Porter", role: "Lyrics By"),
            ]),
        ])
        let credits = RecordSides.from(detail.tracklist)[0].tracks[0].credits
        #expect(credits.map(\.role) == ["Vocals by", "Composed by", "Lyrics by"])
    }

    @Test func writtenByAndWordsByBothMapToWritten() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("A1", "Song", credits: [
                (name: "Author One", role: "Written-By"),
                (name: "Author Two", role: "Words By"),
            ]),
        ])
        let credits = RecordSides.from(detail.tracklist)[0].tracks[0].credits
        #expect(credits == [TrackCredit(role: "Written by", names: ["Author One", "Author Two"])])
    }

    @Test func numericPositionsCollapseToSingleSide() throws {
        let detail = try makeReleaseDetail(tracklist: [track("1", "a"), track("2", "b")])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.count == 1)
        #expect(sides[0].name == "Tracklist")
    }

    /// A 2xLP using Discogs' disc-prefixed convention ("1-A1", "2-A1") must
    /// still produce four sides labelled A/B/C/D — the same as if the
    /// release had used continuous lettering. Disc 2's "A" maps to "C", and
    /// disc 2's "B" maps to "D".
    @Test func discPrefixedPositionsMapToContinuousLettering() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("1-A1", "a1"), track("1-A2", "a2"),
            track("1-B1", "b1"),
            track("2-A1", "c1"),
            track("2-B1", "d1"), track("2-B2", "d2"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.map(\.name) == ["Side A", "Side B", "Side C", "Side D"])
        #expect(sides[2].tracks.map(\.title) == ["c1"])
        #expect(sides[3].tracks.map(\.title) == ["d1", "d2"])
    }

    @Test func dotSeparatedDiscPrefixAlsoWorks() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("1.A1", "a"), track("2.A1", "c"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.map(\.name) == ["Side A", "Side C"])
    }

    @Test func unseparatedDiscPrefixAlsoWorks() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("1A1", "a"), track("2B1", "d"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.map(\.name) == ["Side A", "Side D"])
    }

    @Test func threeDiscReleaseExtendsToSidesEandF() throws {
        let detail = try makeReleaseDetail(tracklist: [
            track("1-A1", "a"), track("2-A1", "c"), track("3-A1", "e"),
        ])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.map(\.name) == ["Side A", "Side C", "Side E"])
    }
}

@MainActor
struct RecordViewModelTests {
    private func sampleRelease() -> CachedRelease {
        CachedRelease(
            releaseId: 42,
            instanceId: 420,
            title: "Album",
            artistDisplayName: "Artist",
            year: 2000,
            dateAdded: .now,
            discogsCoverURL: "",
            thumbURL: ""
        )
    }

    @Test func loadPopulatesSides() async throws {
        let detail = try makeReleaseDetail(tracklist: [track("A1", "One"), track("B1", "Two")])
        let model = RecordViewModel(release: sampleRelease()) { _ in detail }
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.sides.count == 2)
        #expect(model.currentSide?.name == "Side A")
    }

    @Test func flipAdvancesAndStopsAtFinalSide() async throws {
        let detail = try makeReleaseDetail(tracklist: [track("A1", "a"), track("B1", "b")])
        let model = RecordViewModel(release: sampleRelease()) { _ in detail }
        await model.load()

        #expect(model.flipToNextSide() == true)
        #expect(model.currentSide?.name == "Side B")
        #expect(model.isOnFinalSide)
        #expect(model.flipToNextSide() == false)
        #expect(model.currentSide?.name == "Side B")
    }

    @Test func flipBackStepsAndStopsAtFirstSide() async throws {
        let detail = try makeReleaseDetail(tracklist: [track("A1", "a"), track("B1", "b")])
        let model = RecordViewModel(release: sampleRelease()) { _ in detail }
        await model.load()

        #expect(model.flipToPreviousSide() == false) // already on the first side
        model.flipToNextSide()
        #expect(model.currentSide?.name == "Side B")
        #expect(model.flipToPreviousSide() == true)
        #expect(model.currentSide?.name == "Side A")
        #expect(model.flipToPreviousSide() == false)
    }

    @Test func loadFailureSetsFailedState() async {
        let model = RecordViewModel(release: sampleRelease()) { _ in
            throw DiscogsClientError.rateLimited
        }
        await model.load()
        guard case .failed = model.loadState else {
            Issue.record("expected failed state")
            return
        }
    }
}
