import CoreGraphics
import Foundation
import ImageIO

/// A plain-colour image, for covers in tests. Two images of the same colour
/// are "the same sleeve" whatever their size; a different colour is another
/// pressing.
func flatCGImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255, 1]
    )!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// The same image as a PNG file, as a server would send it.
func flatPNG(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> Data {
    let image = flatCGImage(width: width, height: height, red: red, green: green, blue: blue)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
