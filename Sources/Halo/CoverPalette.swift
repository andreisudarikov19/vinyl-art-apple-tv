import SwiftUI
import UIKit

/// A 3-colour palette extracted from an album cover. The halo uses this to
/// emanate cover-derived blobs from behind the record. `dominant` matches the
/// single colour that `CoverColor.dominant` would return so existing call
/// sites stay visually consistent.
struct CoverPalette: Equatable {
    /// Always exactly three colours: dominant, plus two distinct accents.
    let colors: [Color]

    var dominant: Color { colors[0] }
    var accent1: Color { colors[1] }
    var accent2: Color { colors[2] }

    /// Neutral palette used when no cover image is available yet — keeps the
    /// halo from popping in with a wrong colour while artwork loads.
    static let placeholder = CoverPalette(colors: [
        Color(white: 0.22),
        Color(white: 0.16),
        Color(white: 0.10),
    ])
}

@MainActor
extension CoverColor {
    private static var paletteCache: [Int: CoverPalette] = [:]

    /// Three cover-derived colours. The first is the same weighted-average
    /// dominant `CoverColor.dominant` returns (so the radial glow and the
    /// halo agree on the album's main colour); the other two are accent
    /// pixels picked by greedy farthest-point sampling on a downscaled
    /// (16x16) bitmap, each gated by its own colourfulness so a single noisy
    /// dark/grey pixel can't win the accent slot.
    static func palette(from image: UIImage, releaseId: Int) -> CoverPalette {
        if let cached = paletteCache[releaseId] { return cached }
        let dominantColor = dominant(from: image, releaseId: releaseId)
        let (accent1, accent2) = accents(from: image, dominant: dominantColor)
        let result = CoverPalette(colors: [dominantColor, accent1, accent2])
        paletteCache[releaseId] = result
        return result
    }

    private static func accents(from image: UIImage, dominant: Color) -> (Color, Color) {
        guard let cg = image.cgImage else {
            return (CoverPalette.placeholder.colors[1], CoverPalette.placeholder.colors[2])
        }
        let side = 16
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &px, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (CoverPalette.placeholder.colors[1], CoverPalette.placeholder.colors[2])
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Dominant's RGB in 0..255 space, for distance comparisons against
        // raw samples.
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        UIColor(dominant).getRed(&dr, green: &dg, blue: &db, alpha: &da)
        let domR = Double(dr) * 255, domG = Double(dg) * 255, domB = Double(db) * 255

        typealias Sample = (r: Double, g: Double, b: Double, score: Double)
        var samples: [Sample] = []
        samples.reserveCapacity(side * side)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let val = mx / 255.0
            // Score = saturation x value: greys (sat=0) and near-black are out.
            samples.append((r: r, g: g, b: b, score: sat * val))
        }

        func distanceToDominant(_ s: Sample) -> Double {
            let dr = s.r - domR, dg = s.g - domG, db = s.b - domB
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
        func distance(_ a: Sample, _ b: Sample) -> Double {
            let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }

        // Accent 1: farthest from dominant, weighted by own colourfulness so a
        // single noisy dark/grey pixel can't win.
        guard let accent1 = samples.max(by: { a, b in
            (distanceToDominant(a) * a.score) < (distanceToDominant(b) * b.score)
        }) else {
            return (CoverPalette.placeholder.colors[1], CoverPalette.placeholder.colors[2])
        }

        // Accent 2: maximises min distance to both already-picked colours.
        let accent2 = samples.max { a, b in
            let aS = min(distanceToDominant(a), distance(a, accent1)) * a.score
            let bS = min(distanceToDominant(b), distance(b, accent1)) * b.score
            return aS < bS
        } ?? accent1

        return (color(of: accent1), color(of: accent2))
    }

    private static func color(of sample: (r: Double, g: Double, b: Double, score: Double)) -> Color {
        var (r, g, b) = (sample.r, sample.g, sample.b)
        // Lift very dark samples so the blob isn't invisible against black.
        let lum = (r + g + b) / 3
        if lum < 48 {
            let k = 48 / max(lum, 1)
            r = min(r * k, 255); g = min(g * k, 255); b = min(b * k, 255)
        }
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
