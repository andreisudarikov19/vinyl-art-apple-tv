import SwiftUI

// MARK: - The cover view's halo (spec 05)

/// The cover view's light, drawn from `HaloField` and `HaloPalette`
/// (design-handoff/specs/05-cover-view-and-halo.md, "Drawing the halo"):
/// a steady rim round the sleeve, a faint aura, and soft patches drifting
/// outward, combined with a screen blend so overlaps deepen without burning
/// out, under a fine grain. The dark seat and the sleeve go on top, in the
/// record screen. It fades in over three seconds and out in 0.4.
///
/// The screen blend is done in the display's own colour space, not in linear
/// light as the Python reference does, so its brightness wants checking
/// against the reference sheet.
struct HaloLight: View {
    let palette: HaloPalette
    let isEngaged: Bool
    /// The side of the sleeve the light sits behind, centred on the screen.
    var sleeveSide: Double = 820

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow: HaloGlow?
    @State private var level: Double = 0

    /// The light moves slowly; this is plenty.
    private static let framesPerSecond = 15.0
    static let fadeIn: TimeInterval = 3
    static let fadeOut: TimeInterval = 0.4

    var body: some View {
        let layers = self.glow
        let grain = HaloGrain.tile
        return TimelineView(.animation(minimumInterval: 1 / Self.framesPerSecond, paused: !isEngaged)) { timeline in
            // Reduce Motion holds the light still.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(into: &context, size: size, time: time, glow: layers, grain: grain)
            }
        }
        .opacity(level)
        .task(id: palette) {
            // The rim and the aura are fixed shapes: drawn once for a sleeve.
            self.glow = HaloGlow.make(palette: palette, sleeveSide: sleeveSide)
        }
        .onChange(of: isEngaged, initial: true) { _, engaged in
            withAnimation(engaged ? .easeInOut(duration: Self.fadeIn) : .easeOut(duration: Self.fadeOut)) {
                level = engaged ? 1 : 0
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(into context: inout GraphicsContext, size: CGSize, time: TimeInterval, glow: HaloGlow?, grain: CGImage?) {
        let screen = CGRect(origin: .zero, size: size)
        context.fill(Path(screen), with: .color(.black))

        var light = context
        light.blendMode = .screen
        if let glow {
            // The rim breathes very slightly and never goes out.
            var rim = light
            rim.opacity = HaloField.rimLevel(at: time)
            rim.draw(Image(decorative: glow.rim, scale: 1), in: screen)
            light.draw(Image(decorative: glow.aura, scale: 1), in: screen)
        }

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for patch in HaloField.patches(at: time, palette: palette) where patch.opacity > 0.002 {
            let reach = HaloField.patchReach(radius: patch.radius)
            let colour = patch.colour.rgb.color
            // A radial gradient that follows the blurred disc's edge.
            let steps = 14
            let stops = (0...steps).map { step -> Gradient.Stop in
                let share = Double(step) / Double(steps)
                let left = HaloField.patchEdge(distance: share * reach, radius: patch.radius)
                return Gradient.Stop(color: colour.opacity(left * patch.opacity), location: share)
            }
            let middle = CGPoint(x: centre.x + patch.dx, y: centre.y + patch.dy)
            let box = CGRect(x: middle.x - reach, y: middle.y - reach, width: 2 * reach, height: 2 * reach)
            light.fill(
                Path(ellipseIn: box),
                with: .radialGradient(Gradient(stops: stops), center: middle, startRadius: 0, endRadius: reach)
            )
        }

        // A fine grain over the light hides the banding of wide dark gradients.
        if let grain {
            context.fill(Path(screen), with: .tiledImage(Image(decorative: grain, scale: 1)))
        }
    }
}

/// The halo's two fixed layers for one sleeve, as small pictures stretched
/// over the screen: the rim, in the colour of the sleeve's edge on each
/// side, and the aura, in its main colour. Their gradients are wide and
/// soft, so a sixth of the screen's size is enough.
struct HaloGlow {
    let rim: CGImage
    let aura: CGImage

    private static let screen = (width: 1920.0, height: 1080.0)
    private static let scale = 6.0

    static func make(palette: HaloPalette, sleeveSide: Double) -> HaloGlow? {
        let width = Int(screen.width / scale)
        let height = Int(screen.height / scale)
        // The edge colour for every degree round the sleeve.
        let edge = (0..<360).map { palette.edgeColour(at: Double($0) * .pi / 180).rgb }
        let main = palette.main.rgb
        let half = sleeveSide / 2
        let centreX = screen.width / 2
        let centreY = screen.height / 2

        var rim = [UInt8](repeating: 0, count: width * height * 4)
        var aura = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let y = (Double(row) + 0.5) * scale - centreY
            for column in 0..<width {
                let x = (Double(column) + 0.5) * scale - centreX
                // Points outside the sleeve's rectangle; 0 inside it.
                let outside = hypot(max(abs(x) - half, 0), max(abs(y) - half, 0))
                var degrees = Int((atan2(y, x) * 180 / .pi).rounded(.down))
                if degrees < 0 { degrees += 360 }
                let offset = (row * width + column) * 4
                let rimShare = outside / HaloField.rimDepth
                write(edge[degrees % 360], alpha: exp(-rimShare * rimShare) * HaloField.rimStrength, to: &rim, at: offset)
                let auraShare = outside / HaloField.auraDepth
                write(main, alpha: exp(-auraShare * auraShare) * HaloField.auraStrength, to: &aura, at: offset)
            }
        }
        guard let rimImage = image(rim, width: width, height: height),
              let auraImage = image(aura, width: width, height: height) else { return nil }
        return HaloGlow(rim: rimImage, aura: auraImage)
    }

    /// One pixel, with its colour multiplied by its alpha.
    private static func write(_ colour: RGB, alpha: Double, to pixels: inout [UInt8], at offset: Int) {
        let a = min(1, max(0, alpha))
        pixels[offset] = UInt8((colour.r * a * 255).rounded())
        pixels[offset + 1] = UInt8((colour.g * a * 255).rounded())
        pixels[offset + 2] = UInt8((colour.b * a * 255).rounded())
        pixels[offset + 3] = UInt8((a * 255).rounded())
    }

    fileprivate static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// The grain: a tile of faint white specks, the same on every run. It lifts
/// a pixel by up to 1.6% of full scale, 0.8% on average.
@MainActor
enum HaloGrain {
    static let tile: CGImage? = {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 7
        for index in 0..<(side * side) {
            // A small fixed generator, so the tile never changes.
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let speck = UInt8((seed >> 24) % 5)   // 0...4 of 255
            let offset = index * 4
            pixels[offset] = speck
            pixels[offset + 1] = speck
            pixels[offset + 2] = speck
            pixels[offset + 3] = speck
        }
        return HaloGlow.image(pixels, width: side, height: side)
    }()
}
