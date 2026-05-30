import SwiftUI
import UIKit

/// RGB triplet in 0...1 space. Used by the halo to interpolate between
/// colours per-frame without paying the cost of `UIColor(Color(...))` round
/// trips inside the render loop.
struct RGB: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    /// Linear interpolation. `t` is clamped to 0...1.
    static func lerp(_ a: RGB, _ b: RGB, t: Double) -> RGB {
        let clamped = max(0, min(1, t))
        return RGB(
            r: a.r + (b.r - a.r) * clamped,
            g: a.g + (b.g - a.g) * clamped,
            b: a.b + (b.b - a.b) * clamped
        )
    }
}

/// A cover-derived colour palette. Stores both:
/// - `palette`: 3 main colours (dominant + 2 accents) — the blobs' "final"
///   colours after they've drifted out from the cover.
/// - `edges`: 4 edge-region colours (right, bottom, left, top, in that
///   order) — each blob's "starting" colour is the one matching its angle
///   of emergence, so a blob coming out behind the cover's purple top edge
///   starts purple and gradually transitions toward one of the palette
///   colours as it drifts outward.
struct CoverPalette: Equatable {
    /// 3 main colours: dominant, accent1, accent2.
    let palette: [RGB]
    /// 4 edge-region colours, indexed for angle interpolation:
    /// `[right (angle 0), bottom (π/2), left (π), top (3π/2)]`.
    let edges: [RGB]

    /// Bridge to `Color` for non-render-loop callers. Each property reads
    /// the stored `RGB` and converts; cheap because it's not in TimelineView.
    var colors: [Color] { palette.map(\.color) }
    var dominant: Color { palette[0].color }
    var accent1: Color { palette[1].color }
    var accent2: Color { palette[2].color }

    /// Edge colour for a blob emerging at the given angle (radians).
    /// Convention: angle 0 = right, π/2 = bottom, π = left, 3π/2 = top
    /// (SwiftUI's y-axis points down, so this matches screen geometry).
    /// Interpolates linearly between the two nearest edges.
    func edgeColor(at angle: Double) -> RGB {
        var theta = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if theta < 0 { theta += 2 * .pi }
        let edgePos = theta / (.pi / 2) // 0..4
        let lower = Int(edgePos.rounded(.down)) % 4
        let frac = edgePos - Double(lower)
        return RGB.lerp(edges[lower], edges[(lower + 1) % 4], t: frac)
    }

    static let placeholder: CoverPalette = {
        let neutralPalette = [
            RGB(r: 0.22, g: 0.22, b: 0.22),
            RGB(r: 0.16, g: 0.16, b: 0.16),
            RGB(r: 0.10, g: 0.10, b: 0.10),
        ]
        let neutralEdges = Array(repeating: RGB(r: 0.10, g: 0.10, b: 0.10), count: 4)
        return CoverPalette(palette: neutralPalette, edges: neutralEdges)
    }()
}

@MainActor
extension CoverColor {
    private static var paletteCache: [Int: CoverPalette] = [:]

    /// The cover's 3-colour palette plus 4 edge-region colours. `dominant`
    /// in the palette matches the single colour `CoverColor.dominant`
    /// returns (so the radial glow and the halo agree); accents are picked
    /// by greedy farthest-point sampling on a 16x16 downscaled bitmap,
    /// gated by each pixel's own colourfulness. Edge colours come from
    /// weighted-average sampling of a 4-pixel-deep strip along each side
    /// of the same downscaled bitmap. Cached per release.
    static func palette(from image: UIImage, releaseId: Int) -> CoverPalette {
        if let cached = paletteCache[releaseId] { return cached }

        guard let cg = image.cgImage else {
            paletteCache[releaseId] = .placeholder
            return .placeholder
        }
        let side = 16
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &px, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            paletteCache[releaseId] = .placeholder
            return .placeholder
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let dominantColor = dominant(from: image, releaseId: releaseId)
        let dominantRGB = RGB(from: dominantColor)
        let (accent1RGB, accent2RGB) = accentsRGB(pixels: px, side: side, dominant: dominantRGB)
        let edgeRGB = edgeColorsRGB(pixels: px, side: side)

        let result = CoverPalette(
            palette: [dominantRGB, accent1RGB, accent2RGB],
            edges: edgeRGB
        )
        paletteCache[releaseId] = result
        return result
    }

    // MARK: - Accent extraction

    private static func accentsRGB(pixels px: [UInt8], side: Int, dominant: RGB) -> (RGB, RGB) {
        typealias Sample = (r: Double, g: Double, b: Double, score: Double)
        var samples: [Sample] = []
        samples.reserveCapacity(side * side)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let val = mx / 255.0
            samples.append((r: r, g: g, b: b, score: sat * val))
        }

        // Dominant in 0..255 space for comparison with samples.
        let dom255 = (r: dominant.r * 255, g: dominant.g * 255, b: dominant.b * 255)

        func distToDom(_ s: Sample) -> Double {
            let dr = s.r - dom255.r, dg = s.g - dom255.g, db = s.b - dom255.b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        func dist(_ a: Sample, _ b: Sample) -> Double {
            let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }

        guard let accent1 = samples.max(by: { a, b in
            (distToDom(a) * a.score) < (distToDom(b) * b.score)
        }) else {
            return (CoverPalette.placeholder.palette[1], CoverPalette.placeholder.palette[2])
        }
        let accent2 = samples.max { a, b in
            let aS = min(distToDom(a), dist(a, accent1)) * a.score
            let bS = min(distToDom(b), dist(b, accent1)) * b.score
            return aS < bS
        } ?? accent1

        return (sampleToRGB(accent1), sampleToRGB(accent2))
    }

    // MARK: - Edge extraction

    /// Returns 4 colours in order: right, bottom, left, top. Each is the
    /// saturation-weighted average of a 4-pixel-deep strip along that side
    /// of the 16x16 downscaled bitmap.
    private static func edgeColorsRGB(pixels px: [UInt8], side: Int) -> [RGB] {
        // For a 16x16 image, an edge "strip" is 4px deep — wide enough that
        // a single dark border pixel can't dominate, narrow enough that the
        // sampled colour clearly belongs to that side of the cover.
        let depth = 4

        func averageStrip(filter: (_ x: Int, _ y: Int) -> Bool) -> RGB {
            var rT = 0.0, gT = 0.0, bT = 0.0, wT = 0.0
            for y in 0..<side {
                for x in 0..<side where filter(x, y) {
                    let i = (y * side + x) * 4
                    let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
                    let mx = max(r, g, b), mn = min(r, g, b)
                    let sat = mx > 0 ? (mx - mn) / mx : 0
                    let weight = 0.25 + sat
                    rT += r * weight; gT += g * weight; bT += b * weight; wT += weight
                }
            }
            guard wT > 0 else { return RGB(r: 0.1, g: 0.1, b: 0.1) }
            var r = rT / wT, g = gT / wT, b = bT / wT
            let lum = (r + g + b) / 3
            if lum < 48 {
                let k = 48 / max(lum, 1)
                r = min(r * k, 255); g = min(g * k, 255); b = min(b * k, 255)
            }
            return RGB(r: r / 255, g: g / 255, b: b / 255)
        }

        let right  = averageStrip { x, _ in x >= side - depth }
        let bottom = averageStrip { _, y in y >= side - depth }
        let left   = averageStrip { x, _ in x < depth }
        let top    = averageStrip { _, y in y < depth }
        return [right, bottom, left, top]
    }

    // MARK: - Helpers

    private static func sampleToRGB(_ s: (r: Double, g: Double, b: Double, score: Double)) -> RGB {
        var (r, g, b) = (s.r, s.g, s.b)
        let lum = (r + g + b) / 3
        if lum < 48 {
            let k = 48 / max(lum, 1)
            r = min(r * k, 255); g = min(g * k, 255); b = min(b * k, 255)
        }
        return RGB(r: r / 255, g: g / 255, b: b / 255)
    }
}

private extension RGB {
    /// Decomposes a SwiftUI Color into RGB once (so per-frame interpolation
    /// can stay in pure arithmetic).
    init(from color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }
}
