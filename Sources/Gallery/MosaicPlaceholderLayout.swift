import Foundation

/// Where the mosaic has no album, so a placeholder can fill the spot. Pure
/// arithmetic with no SwiftUI, so it can be unit-tested directly.
enum MosaicPlaceholderLayout {
    struct Position: Hashable {
        let row: Int
        let column: Int
    }

    /// The empty positions in reading order: the gap after the last album in
    /// its row, then every position in the rows below, up to `rowCount` rows.
    static func emptyPositions(albumCount: Int, columnCount: Int, rowCount: Int) -> [Position] {
        guard columnCount > 0, rowCount > 0 else { return [] }
        let total = rowCount * columnCount
        let first = max(albumCount, 0)
        guard first < total else { return [] }
        return (first..<total).map { Position(row: $0 / columnCount, column: $0 % columnCount) }
    }

    /// How many rows the mosaic must span: at least the rows the albums need,
    /// and enough rows of `pitch` (one cover plus one gutter) to run from the
    /// top inset down to the bottom of the viewport.
    static func rowCountFillingViewport(
        albumCount: Int,
        columnCount: Int,
        pitch: CGFloat,
        viewportHeight: CGFloat,
        topInset: CGFloat
    ) -> Int {
        guard columnCount > 0 else { return 0 }
        let albumRows = (max(albumCount, 0) + columnCount - 1) / columnCount
        guard pitch > 0, viewportHeight > topInset else { return albumRows }
        let visibleRows = Int(((viewportHeight - topInset) / pitch).rounded(.up))
        return max(albumRows, visibleRows)
    }
}
