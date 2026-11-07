import Foundation
import Testing
@testable import VinylForAppleTV

private func basicInformation(formats: [String] = ["Vinyl"], artists: [String] = ["Artist"]) throws -> BasicInformation {
    let object: [String: Any] = [
        "id": 1,
        "formats": formats.map { ["name": $0, "qty": "1"] },
        "artists": artists.map { ["name": $0] },
    ]
    return try JSONDecoder().decode(BasicInformation.self, from: JSONSerialization.data(withJSONObject: object))
}

struct CachedReleaseTests {
    @Test func parsesDiscogsDateAddedToTheInstant() {
        // 2024-03-01 20:34:56 UTC.
        #expect(CachedRelease.parseDate("2024-03-01T12:34:56-08:00") == Date(timeIntervalSince1970: 1_709_325_296))
    }

    @Test func unreadableDateIsDistantPast() {
        #expect(CachedRelease.parseDate("last Tuesday") == .distantPast)
        #expect(CachedRelease.parseDate("") == .distantPast)
    }

    @Test func galleryAccessibilityLabelReadsArtistThenTitle() {
        let release = CachedRelease(
            releaseId: 1,
            instanceId: 10,
            title: "My Spanish Heart",
            artistDisplayName: "Chick Corea",
            year: 1976,
            dateAdded: .distantPast,
            discogsCoverURL: "",
            thumbURL: ""
        )
        #expect(release.galleryAccessibilityLabel == "Chick Corea – My Spanish Heart")
    }
}

struct BasicInformationTests {
    @Test func vinylIsMatchedWhateverTheCase() throws {
        #expect(try basicInformation(formats: ["vinyl"]).isVinyl)
        #expect(try basicInformation(formats: ["VINYL"]).isVinyl)
    }

    @Test func releaseInSeveralFormatsIsVinylWhenOneIs() throws {
        #expect(try basicInformation(formats: ["CD", "Vinyl"]).isVinyl)
    }

    @Test func releaseWithoutVinylIsNotVinyl() throws {
        #expect(try !basicInformation(formats: ["CD", "Cassette"]).isVinyl)
        #expect(try !basicInformation(formats: []).isVinyl)
    }

    @Test func artistNameDropsDiscogsNumbering() throws {
        #expect(try basicInformation(artists: ["Ghost (2)"]).artistDisplayName == "Ghost")
        #expect(try basicInformation(artists: ["Front 242"]).artistDisplayName == "Front 242")
        #expect(try basicInformation(artists: ["(Hed) P.E."]).artistDisplayName == "(Hed) P.E.")
    }

    @Test func severalArtistsAreJoinedWithCommas() throws {
        #expect(try basicInformation(artists: ["Ghost (2)", "Mastodon", "Gojira"]).artistDisplayName == "Ghost, Mastodon, Gojira")
    }

    @Test func releaseWithoutArtistNamesIsByUnknownArtist() throws {
        #expect(try basicInformation(artists: []).artistDisplayName == "Unknown Artist")
        #expect(try basicInformation(artists: [""]).artistDisplayName == "Unknown Artist")
    }
}
