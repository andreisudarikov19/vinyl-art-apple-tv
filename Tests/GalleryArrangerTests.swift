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
        let result = GalleryArranger.arrange(input, sort: .recentlyAdded, filter: nil)
        #expect(result.map(\.releaseId) == [2, 3, 1])
    }

    @Test func artistSortIsCaseAndLocaleInsensitive() {
        let input = [
            release(id: 1, artist: "Radiohead"),
            release(id: 2, artist: "ABBA"),
            release(id: 3, artist: "beach house"),
        ]
        let result = GalleryArranger.arrange(input, sort: .artist, filter: nil)
        #expect(result.map(\.artistDisplayName) == ["ABBA", "beach house", "Radiohead"])
    }

    @Test func yearSortAscendingWithArtistTieBreak() {
        let input = [
            release(id: 1, artist: "Zz", year: 1999),
            release(id: 2, artist: "Aa", year: 2010),
            release(id: 3, artist: "Mm", year: 1999),
        ]
        let result = GalleryArranger.arrange(input, sort: .year, filter: nil)
        #expect(result.map(\.releaseId) == [3, 1, 2])
    }

    @Test func genreFilterMatchesRecordsCarryingTheGenre() {
        let input = [
            release(id: 1, genres: ["Jazz"], styles: []),
            release(id: 2, genres: ["Rock"], styles: ["Jazz Fusion"]),
            release(id: 3, genres: ["Rock"], styles: ["Indie"]),
        ]
        let byGenre = GalleryArranger.arrange(input, sort: .recentlyAdded, filter: GalleryFilter(genre: "Jazz"))
        #expect(Set(byGenre.map(\.releaseId)) == [1])
        // A style is not a genre: "Jazz Fusion" as a genre matches nothing.
        let byStyleName = GalleryArranger.arrange(input, sort: .recentlyAdded, filter: GalleryFilter(genre: "Jazz Fusion"))
        #expect(byStyleName.isEmpty)
    }

    @Test func styleFilterStaysWithinItsGenre() {
        let input = [
            release(id: 1, genres: ["Electronic"], styles: ["Ambient"]),
            release(id: 2, genres: ["Rock"], styles: ["Ambient"]),
            release(id: 3, genres: ["Electronic"], styles: ["House"]),
        ]
        let filter = GalleryFilter(genre: "Electronic", style: "Ambient")
        let result = GalleryArranger.arrange(input, sort: .recentlyAdded, filter: filter)
        #expect(result.map(\.releaseId) == [1])
    }

    @Test func genreOptionsAreSortedWithCountsAndStylesOfEachGenre() {
        let input = [
            release(id: 1, genres: ["Rock", "Pop"], styles: ["Indie Rock"]),
            release(id: 2, genres: ["Electronic"], styles: ["House", "Ambient"]),
            release(id: 3, genres: ["Electronic"], styles: ["Ambient"]),
            release(id: 4, genres: ["Electronic"], styles: []),
        ]
        let options = GalleryArranger.genreOptions(input)
        #expect(options.map(\.name) == ["Electronic", "Pop", "Rock"])
        #expect(options.map(\.count) == [3, 1, 1])
        let electronic = options[0]
        #expect(electronic.styles.map(\.name) == ["Ambient", "House"])
        #expect(electronic.styles.map(\.count) == [2, 1])
        #expect(options[2].styles == [StyleOption(name: "Indie Rock", count: 1)])
    }

    @Test func genreSortGroupsAlphabeticallyByArtistThenAlbum() {
        let input = [
            release(id: 1, title: "B", artist: "Zed", genres: ["Rock"]),
            release(id: 2, title: "A", artist: "Ana", genres: ["Electronic"]),
            release(id: 3, title: "C", artist: "Ana", genres: ["Rock"]),
            release(id: 4, title: "D", artist: "Abe", genres: ["Rock"]),
        ]
        let result = GalleryArranger.arrange(input, sort: .genre, filter: nil)
        #expect(result.map(\.releaseId) == [2, 4, 3, 1])
    }

    @Test func genreSortListsARecordUnderEachOfItsGenres() {
        let input = [
            release(id: 1, title: "X", artist: "Ana", genres: ["Rock", "Pop"]),
        ]
        let result = GalleryArranger.arrange(input, sort: .genre, filter: nil)
        #expect(result.map(\.releaseId) == [1, 1])
    }

    @Test func genreSortWithAGenreFilterListsOnlyThatGenre() {
        let input = [
            release(id: 1, title: "X", artist: "Ana", genres: ["Rock", "Pop"]),
            release(id: 2, title: "Y", artist: "Bo", genres: ["Pop"]),
        ]
        let result = GalleryArranger.arrange(input, sort: .genre, filter: GalleryFilter(genre: "Pop"))
        #expect(result.map(\.releaseId) == [1, 2])
    }

    @Test func genreSortPutsRecordsWithoutGenreLast() {
        let input = [
            release(id: 1, genres: []),
            release(id: 2, genres: ["Jazz"]),
        ]
        let result = GalleryArranger.arrange(input, sort: .genre, filter: nil)
        #expect(result.map(\.releaseId) == [2, 1])
    }

    @Test func uniquedKeepsTheFirstPlaceOfEachRecord() {
        let input = [
            release(id: 1, genres: ["Rock"]),
            release(id: 2, genres: ["Rock"]),
            release(id: 1, genres: ["Pop"]),
        ]
        #expect(GalleryArranger.uniqued(input).map(\.releaseId) == [1, 2])
    }

    @Test func indexKeepsTheRecordUnderTheNeedleOrStartsAtTheFirst() {
        let input = [release(id: 1), release(id: 2), release(id: 3)]
        #expect(GalleryArranger.index(of: 3, in: input) == 2)
        #expect(GalleryArranger.index(of: 9, in: input) == 0)
        #expect(GalleryArranger.index(of: nil, in: input) == 0)
    }

    @Test func yearSortPutsRecordsWithoutYearLastInTheirOwnGroup() {
        let input = [
            release(id: 1, year: 0),
            release(id: 2, year: 1999),
        ]
        let entries = GalleryArranger.entries(input, sort: .year, filter: nil)
        #expect(entries.map(\.release.releaseId) == [2, 1])
        #expect(entries.map(\.group) == ["1999", "Unknown"])
    }

    @Test func artistAndAlbumSortsGroupByFirstLetter() {
        let input = [
            release(id: 1, title: "Zed", artist: "10cc"),
            release(id: 2, title: "Abbey", artist: "The Beatles"),
        ]
        let byArtist = GalleryArranger.entries(input, sort: .artist, filter: nil)
        #expect(byArtist.map(\.group) == ["#", "T"])
        let byAlbum = GalleryArranger.entries(input, sort: .album, filter: nil)
        #expect(byAlbum.map(\.group) == ["A", "Z"])
    }

    @Test func recentlyAddedGroupsByTheYearAdded() {
        let input = [release(id: 1, daysAgo: 0)]
        let entries = GalleryArranger.entries(input, sort: .recentlyAdded, filter: nil)
        let year = String(Calendar.current.component(.year, from: Date()))
        #expect(entries.map(\.group) == [year])
    }

    @Test func genreSortHasOneEntryPerGenreWithThatGenreAsItsGroup() {
        let input = [
            release(id: 1, title: "X", artist: "Ana", genres: ["Rock", "Pop"]),
            release(id: 2, title: "Y", artist: "Bo", genres: []),
        ]
        let entries = GalleryArranger.entries(input, sort: .genre, filter: nil)
        #expect(entries.map(\.group) == ["Pop", "Rock", "Unknown"])
        #expect(entries.map(\.release.releaseId) == [1, 1, 2])
    }
}
