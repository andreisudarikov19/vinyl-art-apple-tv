import Foundation
import Testing
@testable import VinylForAppleTV

struct GalleryArrangerTests {
    private func release(
        id: Int,
        title: String = "Title",
        artist: String = "Artist",
        year: Int = 2000,
        daysAgo: Double = 0,
        genres: [String] = [],
        styles: [String] = []
    ) -> CachedRelease {
        CachedRelease(
            releaseId: id,
            instanceId: id * 10,
            title: title,
            artistDisplayName: artist,
            year: year,
            dateAdded: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            genres: genres,
            styles: styles,
            discogsCoverURL: "",
            thumbURL: ""
        )
    }

    @Test func recentlyAddedSortsNewestFirst() {
        let input = [
            release(id: 1, daysAgo: 5),
            release(id: 2, daysAgo: 1),
            release(id: 3, daysAgo: 3),
        ]
        let result = GalleryArranger.arrange(input, sort: .recentlyAdded, tag: nil)
        #expect(result.map(\.releaseId) == [2, 3, 1])
    }

    @Test func artistSortIsCaseAndLocaleInsensitive() {
        let input = [
            release(id: 1, artist: "Radiohead"),
            release(id: 2, artist: "ABBA"),
            release(id: 3, artist: "beach house"),
        ]
        let result = GalleryArranger.arrange(input, sort: .artist, tag: nil)
        #expect(result.map(\.artistDisplayName) == ["ABBA", "beach house", "Radiohead"])
    }

    @Test func yearSortAscendingWithArtistTieBreak() {
        let input = [
            release(id: 1, artist: "Zz", year: 1999),
            release(id: 2, artist: "Aa", year: 2010),
            release(id: 3, artist: "Mm", year: 1999),
        ]
        let result = GalleryArranger.arrange(input, sort: .year, tag: nil)
        #expect(result.map(\.releaseId) == [3, 1, 2])
    }

    @Test func tagFilterMatchesGenreOrStyle() {
        let input = [
            release(id: 1, genres: ["Jazz"], styles: []),
            release(id: 2, genres: ["Rock"], styles: ["Jazz Fusion"]),
            release(id: 3, genres: ["Rock"], styles: ["Indie"]),
        ]
        let byGenre = GalleryArranger.arrange(input, sort: .recentlyAdded, tag: "Jazz")
        #expect(Set(byGenre.map(\.releaseId)) == [1])

        let byStyle = GalleryArranger.arrange(input, sort: .recentlyAdded, tag: "Jazz Fusion")
        #expect(Set(byStyle.map(\.releaseId)) == [2])
    }

    @Test func filterTagsAreUniqueSortedUnionOfGenresAndStyles() {
        let input = [
            release(id: 1, genres: ["Rock"], styles: ["Indie Rock"]),
            release(id: 2, genres: ["Jazz"], styles: ["Indie Rock"]),
        ]
        #expect(GalleryArranger.filterTags(input) == ["Indie Rock", "Jazz", "Rock"])
    }
}
