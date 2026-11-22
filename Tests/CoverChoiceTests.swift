import Foundation
import Testing
@testable import VinylForAppleTV

private func flat(_ r: Double, _ g: Double, _ b: Double) -> [RGB] {
    [RGB](repeating: RGB(r: r, g: g, b: b), count: CoverChoice.thumbnailSide * CoverChoice.thumbnailSide)
}

struct CoverChoiceTests {
    private let red = flat(0.65, 0.32, 0.23)
    private let nearlyRed = flat(0.66, 0.33, 0.22)
    private let blue = flat(0.20, 0.30, 0.70)

    private func candidate(_ width: Int, _ height: Int, _ thumbnail: [RGB]) -> CoverChoice.Candidate {
        CoverChoice.Candidate(pixelWidth: width, pixelHeight: height, thumbnail: thumbnail)
    }

    @Test func takesALargerSquareCopyOfTheSamePicture() {
        #expect(CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(1200, 1200, nearlyRed), archiveIsFront: true
        ))
    }

    @Test func refusesAnImageNotMarkedAsTheFront() {
        #expect(!CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(1200, 1200, red), archiveIsFront: false
        ))
    }

    @Test func refusesAnImageThatIsNotClearlyLarger() {
        #expect(!CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(700, 700, red), archiveIsFront: true
        ))
        #expect(CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(750, 750, red), archiveIsFront: true
        ))
    }

    @Test func refusesALessSquareImage() {
        #expect(!CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(1600, 1200, red), archiveIsFront: true
        ))
        // But not when the Discogs image is no better.
        #expect(CoverChoice.prefersArchive(
            discogs: candidate(800, 600, red), archive: candidate(1600, 1200, red), archiveIsFront: true
        ))
    }

    @Test func refusesADifferentPicture() {
        #expect(!CoverChoice.prefersArchive(
            discogs: candidate(600, 600, red), archive: candidate(1200, 1200, blue), archiveIsFront: true
        ))
    }

    @Test func readsSizeAndThumbnailFromAnImage() {
        let candidate = CoverChoice.Candidate(flatCGImage(width: 300, height: 150, red: 200, green: 80, blue: 60))

        #expect(candidate.pixelWidth == 300)
        #expect(candidate.pixelHeight == 150)
        #expect(candidate.thumbnail.count == CoverChoice.thumbnailSide * CoverChoice.thumbnailSide)
        #expect(CoverChoice.difference(candidate.thumbnail, flat(200 / 255, 80 / 255, 60 / 255)) < 0.02)
    }

    @Test func measuresDifference() {
        #expect(CoverChoice.difference(red, red) == 0)
        #expect(CoverChoice.difference(red, nearlyRed) < 0.02)
        #expect(CoverChoice.difference(red, blue) > 0.2)
        #expect(CoverChoice.difference(red, []) == .infinity)
    }
}
