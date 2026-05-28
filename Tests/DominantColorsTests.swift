import SwiftUI
import Testing
import UIKit
@testable import VinylForAppleTV

struct DominantColorsTests {
    @Test func solidImageYieldsThatColor() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let image = renderer.image { context in
            UIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }

        let colors = DominantColors.extract(from: image, gridSize: 4)
        #expect(!colors.isEmpty)

        let components = UIColor(colors[0]).cgColor.components ?? []
        #expect(components.count >= 3)
        #expect(abs(components[0] - 0.2) < 0.1)
        #expect(abs(components[1] - 0.6) < 0.1)
        #expect(abs(components[2] - 0.9) < 0.1)
    }

    @Test func emptyForZeroSizeImage() {
        let image = UIImage()
        #expect(DominantColors.extract(from: image).isEmpty)
    }
}
