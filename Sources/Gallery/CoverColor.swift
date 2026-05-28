import SwiftUI
import UIKit

/// Extracts a representative color from a cover image to tint the CoverFlow
/// background glow. Samples a downscaled copy, weighting toward more saturated
/// pixels so the glow reads as a color rather than mud, and caches per release.
/// Main-actor isolated — it's only used from view code while images load.
@MainActor
enum CoverColor {
    private static var cache: [Int: Color] = [:]

    static func dominant(from image: UIImage, releaseId: Int) -> Color {
        if let cached = cache[releaseId] { return cached }
        let color = extract(from: image)
        cache[releaseId] = color
        return color
    }

    static func extract(from image: UIImage) -> Color {
        guard let cg = image.cgImage else { return .gray }
        let side = 8
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &px, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .gray }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var rT = 0.0, gT = 0.0, bT = 0.0, wT = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i+1]), b = Double(px[i+2])
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let weight = 0.25 + sat // favor colorful samples over flat/gray ones
            rT += r * weight; gT += g * weight; bT += b * weight; wT += weight
        }
        guard wT > 0 else { return .gray }
        var r = rT / wT, g = gT / wT, b = bT / wT

        // Lift very dark averages so the glow stays visible.
        let lum = (r + g + b) / 3
        if lum < 48 {
            let k = 48 / max(lum, 1)
            r = min(r * k, 255); g = min(g * k, 255); b = min(b * k, 255)
        }
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}
