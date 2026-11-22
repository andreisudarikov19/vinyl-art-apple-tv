import UIKit

extension HaloPalette {
    /// The tide's colours for a sleeve: its pixels scaled to 32 by 32, as the halo reads them.
    static func sleeve(from image: UIImage) -> HaloPalette? {
        guard let cg = image.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let rgb = stride(from: 0, to: pixels.count, by: 4).map { i in
            RGB(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
        }
        return HaloPalette(pixels: rgb, side: side)
    }

    /// Before a sleeve is known: neutral grey, as `CoverPalette.placeholder`.
    static let placeholder: HaloPalette = {
        let grey = OKLab(RGB(r: 0.22, g: 0.22, b: 0.22))
        return HaloPalette(colours: [grey, grey, grey], edges: [grey, grey, grey, grey])
    }()
}
