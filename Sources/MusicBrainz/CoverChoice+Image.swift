import CoreGraphics

extension CoverChoice.Candidate {
    /// Reads a decoded image into what `CoverChoice` compares: its size in
    /// pixels, and its thumbnail, squashed to `CoverChoice.thumbnailSide`
    /// squared and read as sRGB in 0...1.
    init(_ image: CGImage) {
        let side = CoverChoice.thumbnailSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        var thumbnail: [RGB] = []
        thumbnail.reserveCapacity(side * side)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            thumbnail.append(RGB(
                r: Double(pixels[index]) / 255,
                g: Double(pixels[index + 1]) / 255,
                b: Double(pixels[index + 2]) / 255
            ))
        }

        self.init(pixelWidth: image.width, pixelHeight: image.height, thumbnail: thumbnail)
    }
}
