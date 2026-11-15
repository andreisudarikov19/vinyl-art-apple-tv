import Foundation
import Testing
@testable import VinylForAppleTV

struct MosaicPlaceholderLayoutTests {
    @Test func fullLastRowLeavesNoGapInThatRow() {
        // Two full rows of seven: nothing empty in the rows that hold albums.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 14, columnCount: 7, rowCount: 2)
        #expect(positions.isEmpty)
    }

    @Test func partialLastRowFillsTheGapAfterTheLastAlbum() {
        // Ten albums: row 1 holds three, so columns 3 to 6 are empty.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 10, columnCount: 7, rowCount: 2)
        #expect(positions.count == 4)
        #expect(positions.first == .init(row: 1, column: 3))
        #expect(positions.last == .init(row: 1, column: 6))
        #expect(positions.allSatisfy { $0.row == 1 })
    }

    @Test func rowsBelowTheLastAlbumAreAllEmpty() {
        // Seven albums fill row 0. Rows 1 to 3 are empty in full.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 7, columnCount: 7, rowCount: 4)
        #expect(positions.count == 21)
        #expect(positions.allSatisfy { $0.row >= 1 })
        #expect(positions.contains(.init(row: 3, column: 6)))
    }

    @Test func emptyCountIsCellsLessAlbums() {
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 23, columnCount: 7, rowCount: 9)
        #expect(positions.count == 9 * 7 - 23)
    }

    @Test func noAlbumsMeansEveryCellIsEmpty() {
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 0, columnCount: 7, rowCount: 2)
        #expect(positions.count == 14)
        #expect(positions.first == .init(row: 0, column: 0))
    }

    @Test func emptyPositionsNeverReachPastTheRequestedRows() {
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 3, columnCount: 7, rowCount: 1)
        #expect(positions.count == 4)
        #expect(positions.allSatisfy { $0.row == 0 })
        #expect(MosaicPlaceholderLayout.emptyPositions(albumCount: 40, columnCount: 7, rowCount: 3).isEmpty)
    }

    @Test func rowsRunDownToTheBottomOfTheViewport() {
        // Pitch 274.6 pt, a 1080 pt screen with a 150 pt top inset: 930 pt of
        // grid is 3.39 pitches, so four rows reach the bottom edge.
        let rows = MosaicPlaceholderLayout.rowCountFillingViewport(
            albumCount: 3,
            columnCount: 7,
            pitch: 274.6,
            viewportHeight: 1080,
            topInset: 150
        )
        #expect(rows == 4)
        let covered = 150 + CGFloat(rows) * 274.6
        #expect(covered >= 1080)
    }

    @Test func albumRowsWinWhenTheLibraryIsTall() {
        // 100 albums need 15 rows, which is more than the screen shows.
        let rows = MosaicPlaceholderLayout.rowCountFillingViewport(
            albumCount: 100,
            columnCount: 7,
            pitch: 274.6,
            viewportHeight: 1080,
            topInset: 150
        )
        #expect(rows == 15)
    }

    @Test func unmeasuredViewportFallsBackToAlbumRows() {
        // Before the first layout the viewport is zero, so only the album rows count.
        let rows = MosaicPlaceholderLayout.rowCountFillingViewport(
            albumCount: 10,
            columnCount: 7,
            pitch: 0,
            viewportHeight: 0,
            topInset: 150
        )
        #expect(rows == 2)
    }
}
