import Foundation
import Testing
@testable import VinylForAppleTV

private func makeReleaseDetail(tracklist: [[String: Any]]) throws -> ReleaseDetail {
    let object: [String: Any] = ["id": 1, "title": "Album", "tracklist": tracklist]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(ReleaseDetail.self, from: data)
}

private func track(_ position: String, _ title: String, duration: String = "3:00", type: String = "track") -> [String: Any] {
    ["position": position, "title": title, "duration": duration, "type_": type]
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

    @Test func numericPositionsCollapseToSingleSide() throws {
        let detail = try makeReleaseDetail(tracklist: [track("1", "a"), track("2", "b")])
        let sides = RecordSides.from(detail.tracklist)
        #expect(sides.count == 1)
        #expect(sides[0].name == "Tracklist")
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
