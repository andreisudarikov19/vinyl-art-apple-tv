import Foundation

/// The mosaic's matrix: an endless grid of cover-sized cells, of which the
/// albums occupy the first positions in reading order. Every other cell is
/// empty and gets a placeholder. Rows above the first row are always empty, so
/// the matrix runs above the collection as well as below it. Pure arithmetic
/// with no SwiftUI, so it can be unit-tested directly.
enum MosaicPlaceholderLayout {
    struct Position: Hashable {
        /// Negative rows lie above the first row of albums.
        let row: Int
        let column: Int
    }

    /// Whether the cell at (`row`, `column`) holds no album. Album `index`
    /// sits at row `index / columnCount`, column `index % columnCount`.
    static func isEmpty(row: Int, column: Int, albumCount: Int, columnCount: Int) -> Bool {
        guard row >= 0 else { return true }
        return row * columnCount + column >= max(albumCount, 0)
    }

    /// The empty positions in the given rows, in reading order.
    static func emptyPositions(albumCount: Int, columnCount: Int, rows: Range<Int>) -> [Position] {
        guard columnCount > 0 else { return [] }
        return rows.flatMap { row in
            (0..<columnCount).compactMap { column in
                isEmpty(row: row, column: column, albumCount: albumCount, columnCount: columnCount)
                    ? Position(row: row, column: column)
                    : nil
            }
        }
    }

    /// The rows of the matrix that a region from the top edge (y = 0) to
    /// `height` reaches. Row 0 starts at `topInset`, and each row is `pitch`
    /// tall (one cover plus one gutter). One extra row is kept on each side as
    /// margin, so the matrix runs past both edges of the region.
    static func rows(topInset: CGFloat, pitch: CGFloat, height: CGFloat) -> Range<Int> {
        guard pitch > 0, height > 0 else { return 0..<0 }
        let first = Int((-topInset / pitch).rounded(.down)) - 1
        let last = Int(((height - topInset) / pitch).rounded(.up)) + 1
        return first..<max(first, last)
    }
}
