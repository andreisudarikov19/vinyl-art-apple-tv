import SwiftUI
import Testing
import UIKit
@testable import VinylForAppleTV

private let red = RGB(r: 220 / 255, g: 30 / 255, b: 30 / 255)
private let blue = RGB(r: 30 / 255, g: 30 / 255, b: 220 / 255)

/// A 64x64 cover in plain sRGB, filled by `draw` in UIKit coordinates (y down).
private func cover(_ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image(actions: draw)
}

private func solidCover(_ color: RGB) -> UIImage {
    cover { context in
        color.uiColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}

/// `first` on the left or top half, `second` on the other.
private func splitCover(_ first: RGB, _ second: RGB, sideBySide: Bool) -> UIImage {
    cover { context in
        first.uiColor.setFill()
        context.fill(sideBySide ? CGRect(x: 0, y: 0, width: 32, height: 64) : CGRect(x: 0, y: 0, width: 64, height: 32))
        second.uiColor.setFill()
        context.fill(sideBySide ? CGRect(x: 32, y: 0, width: 32, height: 64) : CGRect(x: 0, y: 32, width: 64, height: 32))
    }
}

private func isClose(_ a: RGB, _ b: RGB, within tolerance: Double = 0.02) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
}

private func distance(_ a: RGB, _ b: RGB) -> Double {
    ((a.r - b.r) * (a.r - b.r) + (a.g - b.g) * (a.g - b.g) + (a.b - b.b) * (a.b - b.b)).squareRoot()
}

private extension RGB {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: r, g: g, b: b)
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

/// The palette and colour caches are global, so each test takes release ids
/// no other test uses. Negative ids can't collide with real releases.
@MainActor
private var lastReleaseId = 0

@MainActor
private func unusedReleaseId() -> Int {
    lastReleaseId -= 1
    return lastReleaseId
}

@MainActor
struct CoverPaletteTests {
    private let edges = CoverPalette(
        palette: Array(repeating: RGB(r: 0, g: 0, b: 0), count: 3),
        edges: [
            RGB(r: 1, g: 0, b: 0), // right
            RGB(r: 0, g: 1, b: 0), // bottom
            RGB(r: 0, g: 0, b: 1), // left
            RGB(r: 1, g: 1, b: 1), // top
        ]
    )

    @Test func solidCoverIsDominantAndOnEveryEdge() {
        let palette = CoverColor.palette(from: solidCover(red), releaseId: unusedReleaseId())

        #expect(isClose(palette.palette[0], red))
        for edge in palette.edges {
            #expect(isClose(edge, red))
        }
    }

    @Test func sideBySideHalvesColourTheLeftAndRightEdges() {
        let palette = CoverColor.palette(from: splitCover(red, blue, sideBySide: true), releaseId: unusedReleaseId())

        #expect(isClose(palette.edges[2], red))
        #expect(isClose(palette.edges[0], blue))
    }

    @Test func stackedHalvesColourTheTopAndBottomEdges() {
        let palette = CoverColor.palette(from: splitCover(red, blue, sideBySide: false), releaseId: unusedReleaseId())

        #expect(isClose(palette.edges[3], red))
        #expect(isClose(palette.edges[1], blue))
    }

    @Test func edgeColorAtEachSideIsThatEdge() {
        #expect(isClose(edges.edgeColor(at: 0), edges.edges[0], within: 1e-9))
        #expect(isClose(edges.edgeColor(at: .pi / 2), edges.edges[1], within: 1e-9))
        #expect(isClose(edges.edgeColor(at: .pi), edges.edges[2], within: 1e-9))
        #expect(isClose(edges.edgeColor(at: 3 * .pi / 2), edges.edges[3], within: 1e-9))
    }

    @Test func edgeColorBlendsBetweenNeighbouringEdges() {
        #expect(isClose(edges.edgeColor(at: .pi / 4), RGB(r: 0.5, g: 0.5, b: 0), within: 1e-9))
        #expect(isClose(edges.edgeColor(at: 7 * .pi / 4), RGB(r: 1, g: 0.5, b: 0.5), within: 1e-9))
    }

    @Test func edgeColorWrapsAnglesOutsideOneTurn() {
        #expect(isClose(edges.edgeColor(at: -.pi / 2), edges.edges[3], within: 1e-9))
        #expect(isClose(edges.edgeColor(at: 2 * .pi), edges.edges[0], within: 1e-9))
        #expect(isClose(edges.edgeColor(at: 2 * .pi + .pi / 2), edges.edges[1], within: 1e-9))
    }

    @Test func lerpClampsT() {
        let a = RGB(r: 0, g: 0, b: 0)
        let b = RGB(r: 1, g: 0.5, b: 0.25)

        #expect(RGB.lerp(a, b, t: -1) == a)
        #expect(RGB.lerp(a, b, t: 0.5) == RGB(r: 0.5, g: 0.25, b: 0.125))
        #expect(RGB.lerp(a, b, t: 2) == b)
    }

    @Test func paletteIsCachedPerRelease() {
        let releaseId = unusedReleaseId()
        let first = CoverColor.palette(from: solidCover(red), releaseId: releaseId)

        #expect(CoverColor.palette(from: solidCover(blue), releaseId: releaseId) == first)
        #expect(CoverColor.palette(from: solidCover(blue), releaseId: unusedReleaseId()) != first)
    }
}

@MainActor
struct CoverColorTests {
    @Test func nearBlackCoverIsLiftedToStayVisible() {
        let color = RGB(CoverColor.extract(from: solidCover(RGB(r: 10 / 255, g: 10 / 255, b: 10 / 255))))

        #expect((color.r + color.g + color.b) / 3 >= 0.18)
    }

    @Test func saturatedPixelsOutweighGreyOnes() {
        let saturated = RGB(r: 1, g: 0, b: 0)
        let grey = RGB(r: 0.5, g: 0.5, b: 0.5)
        let mean = RGB.lerp(saturated, grey, t: 0.5)

        let color = RGB(CoverColor.extract(from: splitCover(saturated, grey, sideBySide: true)))

        #expect(distance(color, saturated) < distance(mean, saturated) / 2)
    }

    @Test func dominantColourIsCachedPerRelease() {
        let releaseId = unusedReleaseId()
        let first = CoverColor.dominant(from: solidCover(red), releaseId: releaseId)

        #expect(CoverColor.dominant(from: solidCover(blue), releaseId: releaseId) == first)
        #expect(CoverColor.dominant(from: solidCover(blue), releaseId: unusedReleaseId()) != first)
    }
}
