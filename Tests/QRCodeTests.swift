import CoreImage
import Testing
import UIKit
@testable import VinylForAppleTV

struct QRCodeTests {
    @Test func encodesAuthorizeURLThatScansBack() throws {
        let payload = "https://www.discogs.com/oauth/authorize?oauth_token=abc123"
        let image = try #require(QRCode.image(from: payload))
        let ciImage = try #require(CIImage(image: image))

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let messages = (detector?.features(in: ciImage) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }

        #expect(messages.contains(payload))
    }

    @Test func scaleControlsOutputSize() throws {
        let small = try #require(QRCode.image(from: "payload", scale: 4))
        let large = try #require(QRCode.image(from: "payload", scale: 12))
        #expect(large.size.width > small.size.width)
    }
}
