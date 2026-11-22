import Foundation
import Testing
@testable import VinylForAppleTV

struct MosaicPlaceholderLayoutTests {
    /// Cover pitch on a 1920 pt wide screen with 7 columns and a 2 pt gutter.
    private let pitch: CGFloat = 274.6
    private let topInset: CGFloat = 150

    @Test func fullLastRowLeavesNoGapInThatRow() {
        // Two full rows of seven: nothing empty in the rows that hold albums.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 14, columnCount: 7, rows: 0..<2)
        #expect(positions.isEmpty)
    }

    @Test func partialLastRowFillsTheGapAfterTheLastAlbum() {
        // Ten albums: row 1 holds three, so columns 3 to 6 are empty.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 10, columnCount: 7, rows: 0..<2)
        #expect(positions.count == 4)
        #expect(positions.first == .init(row: 1, column: 3))
        #expect(positions.last == .init(row: 1, column: 6))
    }

    @Test func rowsAboveTheFirstRowAreAllEmpty() {
        // Seven albums fill row 0. Row -1 sits above the collection and is empty in full.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 7, columnCount: 7, rows: -1..<1)
        #expect(positions.count == 7)
        #expect(positions.allSatisfy { $0.row == -1 })
    }

    @Test func rowsBelowTheLastAlbumAreAllEmpty() {
        // Seven albums fill row 0. Rows 1 to 3 are empty in full.
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 7, columnCount: 7, rows: 0..<4)
        #expect(positions.count == 21)
        #expect(positions.allSatisfy { $0.row >= 1 })
        #expect(positions.contains(.init(row: 3, column: 6)))
    }

    @Test func emptyCountIsCellsLessAlbums() {
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 23, columnCount: 7, rows: 0..<9)
        #expect(positions.count == 9 * 7 - 23)
    }

    @Test func noAlbumsMeansEveryCellIsEmpty() {
        let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: 0, columnCount: 7, rows: 0..<2)
        #expect(positions.count == 14)
        #expect(positions.first == .init(row: 0, column: 0))
    }

    @Test func noPlaceholderSitsOnAnAlbum() {
        // Every position the matrix draws is an empty cell, for a few album counts and
        // a range that runs above and below the albums.
        for albumCount in [0, 1, 6, 7, 10, 21, 22] {
            let positions = MosaicPlaceholderLayout.emptyPositions(albumCount: albumCount, columnCount: 7, rows: -2..<6)
            for position in positions {
                #expect(position.row < 0 || position.row * 7 + position.column >= albumCount)
            }
        }
    }

    @Test func matrixRunsAboveTheFirstRow() {
        // Row 0 starts at the top inset, so row -1 is the one just above it and
        // row -2 is a further margin row. Both lie above the first album.
        let rows = MosaicPlaceholderLayout.rows(topInset: topInset, pitch: pitch, height: 1080)
        #expect(rows.contains(-1))
        #expect(rows.lowerBound <= -1)
    }

    @Test func matrixReachesPastTheBottomEdgeOfTheScreen() {
        // The row holding the bottom edge of a 1080 pt screen is row 3 (its top is
        // 150 + 3 * 274.6 = 973.8). The matrix must include it, and one row more.
        let rows = MosaicPlaceholderLayout.rows(topInset: topInset, pitch: pitch, height: 1080)
        let bottomRow = Int(((1080 - topInset) / pitch).rounded(.down))
        #expect(bottomRow == 3)
        #expect(rows.contains(bottomRow))
        #expect(rows.upperBound > bottomRow + 1)
    }

    @Test func matrixBelowTheLastAlbumCoversTheScreenWhateverTheAlbumCount() {
        // Three albums end in row 0. The matrix must still reach the bottom edge.
        let rows = MosaicPlaceholderLayout.rows(topInset: topInset, pitch: pitch, height: 1080)
        let below = MosaicPlaceholderLayout.emptyPositions(albumCount: 3, columnCount: 7, rows: rows)
        #expect(below.contains(.init(row: 3, column: 0)))
        #expect(below.contains(.init(row: 3, column: 6)))
    }

    @Test func noPitchOrNoHeightMeansNoMatrix() {
        #expect(MosaicPlaceholderLayout.rows(topInset: topInset, pitch: 0, height: 1080).isEmpty)
        #expect(MosaicPlaceholderLayout.rows(topInset: topInset, pitch: pitch, height: 0).isEmpty)
    }
}

struct GridMeasuresTests {
    private let grid = GridMeasures(size: CGSize(width: 1920, height: 1080), count: 30)

    @Test func fourRowsHangEightPointsOverTheTopAndTheBottom() {
        #expect(abs(grid.side - 272.571) < 0.01)
        #expect(abs(grid.overhang - 8.143) < 0.01)
        #expect(abs(grid.wallOffset(topRow: 0) + 8.143) < 0.01)
    }

    @Test func theRowInFocusIsTheSecondWhereTheEndsAllow() {
        // 30 records are five rows, so the wall can move up by one row only.
        #expect(GridMeasures.topRow(forIndex: 0, count: 30) == 0)
        #expect(GridMeasures.topRow(forIndex: 7, count: 30) == 0)
        #expect(GridMeasures.topRow(forIndex: 14, count: 30) == 1)
        #expect(GridMeasures.topRow(forIndex: 29, count: 30) == 1)
        // A long wall: the row in focus is second from the top.
        #expect(GridMeasures.topRow(forIndex: 70, count: 700) == 9)
        // A wall shorter than the screen never moves.
        #expect(GridMeasures.topRow(forIndex: 13, count: 14) == 0)
    }

    @Test func theCardStaysInsideTheSafeArea() {
        let first = grid.cardFrame(index: 0, topRow: 0)
        #expect(first.minX == 80 && first.minY == 60)
        let lastColumn = grid.cardFrame(index: 6, topRow: 0)
        #expect(abs(lastColumn.maxX - (1920 - 80)) < 0.001)
        // In the middle of the wall the card's sleeve is centred on its cell.
        let middle = grid.cardFrame(index: 10, topRow: 0)
        let cell = grid.cellFrame(index: 10, topRow: 0)
        #expect(abs(middle.midX - cell.midX) < 0.001)
        #expect(abs(middle.minY + 10 + 161 - cell.midY) < 0.001)
    }
}
