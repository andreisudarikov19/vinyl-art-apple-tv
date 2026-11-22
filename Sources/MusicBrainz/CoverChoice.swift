import Foundation

/// Decides whether a Cover Art Archive image may replace the Discogs cover.
///
/// The Discogs cover is the default. Today `CoverArtService` swaps it for
/// whatever the archive returns, which is how a smaller, differently shaped
/// or simply different picture ends up on screen. An archive image now has
/// to be *better*: the front cover, clearly larger, at least as square, and
/// the same picture.
///
/// The decision needs both images loaded, so it runs after the archive image
/// arrives, once per record, and its result is stored
/// (see design-handoff/specs/07-cover-image-choice.md).
enum CoverChoice {
    /// What the rule needs to know about one image.
    struct Candidate: Equatable, Sendable {
        var pixelWidth: Int
        var pixelHeight: Int
        /// The image scaled down to `thumbnailSide` squared, row by row,
        /// squashed to a square whatever its shape. sRGB in 0...1.
        var thumbnail: [RGB]

        var shorterSide: Int { min(pixelWidth, pixelHeight) }

        /// 0 for a square; grows as the image gets longer or taller.
        var offSquare: Double {
            guard pixelWidth > 0, pixelHeight > 0 else { return .infinity }
            return abs(1 - Double(pixelWidth) / Double(pixelHeight))
        }
    }

    static let thumbnailSide = 8

    struct Thresholds: Equatable, Sendable {
        /// The archive image's shorter side must be at least this many times
        /// the Discogs image's.
        var minimumSizeGain = 1.25
        /// How much less square than the Discogs image it may be.
        var squarenessSlack = 0.02
        /// Largest mean OKLab distance between the two thumbnails for them
        /// to count as the same picture. A starting value: tune it on real
        /// pairs (same sleeve scanned twice, and two different pressings).
        var maximumDifference = 0.08

        init() {}
    }

    /// - Parameter archiveIsFront: The archive's own `front` flag for the
    ///   image. An image that is merely first in the list does not qualify.
    static func prefersArchive(
        discogs: Candidate,
        archive: Candidate,
        archiveIsFront: Bool,
        thresholds: Thresholds = Thresholds()
    ) -> Bool {
        guard archiveIsFront else { return false }
        guard Double(archive.shorterSide) >= Double(discogs.shorterSide) * thresholds.minimumSizeGain else {
            return false
        }
        guard archive.offSquare <= discogs.offSquare + thresholds.squarenessSlack else { return false }
        return difference(discogs.thumbnail, archive.thumbnail) <= thresholds.maximumDifference
    }

    /// Mean OKLab distance between two thumbnails of the same size.
    /// `.infinity` if they cannot be compared.
    static func difference(_ a: [RGB], _ b: [RGB]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var total = 0.0
        for (p, q) in zip(a, b) {
            total += OKLab(p).distanceSquared(to: OKLab(q)).squareRoot()
        }
        return total / Double(a.count)
    }
}
