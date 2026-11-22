import Testing
@testable import VinylForAppleTV

struct GalleryToolbarTests {
    @Test func menuRowsReturnFocusToTheirControl() {
        #expect(ToolbarFocus.sortRow(.album).control == .sort)
        #expect(ToolbarFocus.genreRow("Rock").control == .genre)
        #expect(ToolbarFocus.styleRow(nil).control == .genre)
        #expect(ToolbarFocus.suggest.control == .suggest)
        #expect(ToolbarFocus.settings.control == .settings)
    }

    @Test func sortMenuOpensOnTheCurrentSort() {
        #expect(ToolbarRules.openFocus(for: .sort, sort: .year, filter: nil) == .sortRow(.year))
    }

    @Test func genreMenuOpensOnTheCurrentGenreOrStyle() {
        #expect(ToolbarRules.openFocus(for: .genre, sort: .year, filter: nil) == .genreRow(nil))
        let genre = GalleryFilter(genre: "Electronic")
        #expect(ToolbarRules.openFocus(for: .genre, sort: .year, filter: genre) == .genreRow("Electronic"))
        let style = GalleryFilter(genre: "Electronic", style: "Ambient")
        #expect(ToolbarRules.openFocus(for: .genre, sort: .year, filter: style) == .styleRow("Ambient"))
    }

    @Test func styleColumnReopensOnlyWhenAStyleIsInUse() {
        #expect(ToolbarRules.openStyleGenre(for: nil) == nil)
        #expect(ToolbarRules.openStyleGenre(for: GalleryFilter(genre: "Rock")) == nil)
        #expect(ToolbarRules.openStyleGenre(for: GalleryFilter(genre: "Electronic", style: "Ambient")) == "Electronic")
    }

    @Test func sortIsOrderedWithGenreLast() {
        #expect(GallerySort.allCases.map(\.displayName) == ["Recently added", "Artist", "Album", "Year", "Genre"])
    }
}
