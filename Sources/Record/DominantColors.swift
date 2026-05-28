import CoreGraphics
import SwiftUI
import UIKit

/// Extracts a small palette of representative colors from a cover image to
/// drive the cover-focused ambient gradient.
enum DominantColors {
    static func extract(from url: URL, gridSize: Int = 8) async -> [Color] {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return [] }
        return extract(from: image, gridSize: gridSize)
    }

    static func extract(from image: UIImage, gridSize: Int = 8) -> [Color] {
        guard let cgImage = image.cgImage else { return [] }

        let width = gridSize
        let height = gridSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var seen: Set<UInt32> = []
        var colors: [Color] = []
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let r = pixels[index]
            let g = pixels[index + 1]
            let b = pixels[index + 2]

            // Quantize so near-identical samples collapse to one swatch.
            let key = (UInt32(r / 32) << 16) | (UInt32(g / 32) << 8) | UInt32(b / 32)
            guard seen.insert(key).inserted else { continue }
            colors.append(Color(
                red: Double(r) / 255,
                green: Double(g) / 255,
                blue: Double(b) / 255
            ))
        }
        return colors
    }
}
