import SwiftUI

/// Visual tuning for a halo. CoverFlow uses `.standard` (smaller, simpler);
/// cover-focused uses `.rich` (more blobs, larger reach, breathing ambient
/// base, plus a second tier of edge-origin blobs that fade in after the halo
/// has been continuously engaged for a while).
struct HaloStyle {
    /// Centre-origin blob count — all four (or six) emerge from behind the cover.
    var blobCount: Int = 4
    var blobSize: CGFloat = 700
    var blobBlur: CGFloat = 100
    /// How far a centre-origin blob travels from screen centre over its lifecycle.
    var maxDriftDistance: Double = 700
    /// If true, a low-opacity full-screen gradient pulses gently underneath
    /// the blobs so the corners aren't dead black between blob cycles.
    var ambientBase: Bool = false
    /// If non-nil, additional blobs originate at the cover's perimeter (not its
    /// centre) and fade in once the halo has been engaged this many seconds.
    /// They drift outward toward the screen's corners. Resets each engagement.
    var edgeBlobsAfter: TimeInterval? = nil
    var edgeBlobCount: Int = 4
    /// Distance from screen centre to the cover's edge — defines where
    /// edge-origin blobs are born. Ignored when `edgeBlobsAfter` is nil.
    var coverHalfExtent: Double = 0
    /// When true, each blob's starting colour matches the cover's edge tint
    /// at its emergence angle, transitioning toward a palette colour over
    /// its lifecycle. When false, blobs are a flat palette colour (the
    /// CoverFlow look — leave it alone, it's already right).
    var directionalColor: Bool = false
    /// When true, each blob's diameter is varied by a deterministic hash so
    /// the wall reads organic rather than uniform.
    var variableSize: Bool = false

    /// CoverFlow's halo: small carousel, plenty of "frame" around it, so a
    /// modest set of blobs already fills the visible field nicely.
    static let standard = HaloStyle()

    /// Cover-focused / ambient art screen: the cover dominates the frame, so
    /// a sparse set of blobs reads as cheap. Layers a breathing base coat,
    /// more + bigger centre blobs, and (after 60s) edge-origin blobs that
    /// reach into the corners.
    static let rich = HaloStyle(
        blobCount: 6,
        blobSize: 1000,
        blobBlur: 110,
        maxDriftDistance: 1000,
        ambientBase: true,
        edgeBlobsAfter: 60,
        edgeBlobCount: 4,
        coverHalfExtent: 410, // half of the 820pt cover-focused cover
        directionalColor: true,
        variableSize: true
    )
}

/// Entry ramp for a halo engaged for `elapsed` seconds: 0 at the moment it
/// engages, rising linearly to 1 over `fadeIn` seconds and holding there.
/// Clamped to 0...1, so a negative elapsed time reads as "not yet" and a
/// zero fade reads as "already in" rather than dividing by zero.
func haloEntryRamp(elapsed: TimeInterval, fadeIn: TimeInterval) -> Double {
    guard fadeIn > 0 else { return 1 }
    return min(1, max(0, elapsed / fadeIn))
}

/// Cover-derived ambient halo. Heavily-blurred colour blobs anchored at the
/// view's centre (behind the album cover), drifting outward in staggered
/// directions and composited with `.plusLighter` so overlaps bloom. The
/// cover is meant to be drawn on top of this view in the parent ZStack so
/// blobs only become visible past its silhouette — the "halo emanating from
/// behind the record" reading.
///
/// The `style` parameter selects between the two presets above. The two are
/// rendered by the same code path; `.rich` just turns more layers on.
struct HaloView: View {
    let palette: CoverPalette
    let isEngaged: Bool
    var style: HaloStyle = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderedOpacity: Double = 0
    /// Timestamp the halo most recently became engaged. Drives the
    /// "edge blobs fade in after N seconds" effect. Cleared on disengagement
    /// so each new engagement starts the countdown fresh.
    @State private var engagedAt: Date?

    private let liveLifetime: Double = 18 // seconds per centre-blob cycle
    private let reducedLifetime: Double = 32
    private let fadeInSeconds: Double = 3
    private let fadeOutSeconds: Double = 0.4
    private let edgeLifetime: Double = 22
    private let edgeReducedLifetime: Double = 38
    private let edgeFadeInSeconds: Double = 4

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let elapsedEngaged = engagedAt.map { context.date.timeIntervalSince($0) } ?? 0
                // Centre blobs ease in with the engagement. With no engagement
                // start (disengaged, so fading out) the ramp holds at 1 and
                // renderedOpacity alone takes the halo down over fadeOutSeconds.
                let entry = engagedAt == nil
                    ? 1
                    : haloEntryRamp(elapsed: elapsedEngaged, fadeIn: fadeInSeconds)
                ZStack {
                    if style.ambientBase {
                        ambientBase(time: t)
                    }
                    ForEach(0..<style.blobCount, id: \.self) { index in
                        centerBlob(at: index, time: t, center: center, entry: entry)
                    }
                    if let edgeStart = style.edgeBlobsAfter,
                       elapsedEngaged >= edgeStart {
                        let fadeIn = haloEntryRamp(elapsed: elapsedEngaged - edgeStart, fadeIn: edgeFadeInSeconds)
                        ForEach(0..<style.edgeBlobCount, id: \.self) { index in
                            edgeBlob(at: index, time: t, center: center, fadeIn: fadeIn)
                        }
                    }
                }
            }
        }
        .opacity(renderedOpacity)
        .allowsHitTesting(false)
        .onAppear {
            if isEngaged {
                engagedAt = Date()
                // Mounted already engaged: fade in from the initial 0, the same
                // as an engagement that starts while the view is on screen.
                withAnimation(.easeInOut(duration: fadeInSeconds)) {
                    renderedOpacity = 1
                }
            } else {
                renderedOpacity = 0
            }
        }
        .onChange(of: isEngaged) { _, new in
            engagedAt = new ? Date() : nil
            withAnimation(.easeInOut(duration: new ? fadeInSeconds : fadeOutSeconds)) {
                renderedOpacity = new ? 1 : 0
            }
        }
    }

    // MARK: - Layers

    /// Soft full-screen radial gradient in the album's dominant colour. Slowly
    /// breathes its opacity in and out so corners between centre-blob cycles
    /// still carry a faint cover tint instead of going black.
    private func ambientBase(time: TimeInterval) -> some View {
        let period: Double = reduceMotion ? 24 : 12
        let breath = (sin(time * 2 * .pi / period) + 1) / 2 // 0..1
        let amplitude: Double = reduceMotion ? 0.06 : 0.12
        let baseline: Double = 0.08
        let opacity = baseline + amplitude * breath

        return RadialGradient(
            gradient: Gradient(stops: [
                .init(color: palette.dominant.opacity(opacity), location: 0),
                .init(color: palette.dominant.opacity(opacity * 0.4), location: 0.6),
                .init(color: .clear, location: 1.0),
            ]),
            center: .center,
            startRadius: 120,
            endRadius: 1200
        )
        .ignoresSafeArea()
        .blendMode(.plusLighter)
    }

    /// A centre-origin blob: born at the view's centre (behind the cover),
    /// drifting outward in its assigned direction. The blob's starting
    /// colour matches the cover's edge it emerges past; over its lifecycle
    /// it gradually transitions toward one of the 3 palette colours. The
    /// rich style also varies each blob's diameter so the wall of blobs
    /// reads organic rather than uniform.
    @ViewBuilder
    private func centerBlob(at index: Int, time: TimeInterval, center: CGPoint, entry: Double) -> some View {
        let lifetime = reduceMotion ? reducedLifetime : liveLifetime
        let phaseOffset = Double(index) * (lifetime / Double(style.blobCount))
        let cycleTime = (time + phaseOffset).truncatingRemainder(dividingBy: lifetime)
        let progress = cycleTime / lifetime

        let baseAngle = Double(index) * (2 * .pi / Double(style.blobCount))
        let angleWobble = reduceMotion ? 0 : sin(time / 11.0) * 0.25
        let angle = baseAngle + angleWobble
        let distance = progress * style.maxDriftDistance
        let dx = cos(angle) * distance
        let dy = sin(angle) * distance

        let scaleBase = 0.5 + 0.6 * progress
        let pulse = reduceMotion ? 0 : sin(time * 1.3 + Double(index) * 0.7) * 0.10
        let scale = scaleBase + pulse

        let blobOpacity = sin(progress * .pi) * 0.85 * entry

        // Direction-matched colour (rich style only): start = the cover-edge
        // tint matching the blob's emergence angle, end = one of the 3
        // palette colours (cycling). Smoothstep over progress so the
        // transition reads as a slow shift, not a linear fade. CoverFlow's
        // standard style keeps each blob a single palette colour so the
        // confirmed-good look there doesn't regress.
        let renderedColour = blobColor(index: index, baseAngle: baseAngle, progress: progress)
        let sizeMult: CGFloat = style.variableSize
            ? sizeMultiplier(forIndex: index, count: style.blobCount)
            : 1.0
        let actualSize = style.blobSize * sizeMult

        Circle()
            .fill(renderedColour)
            .frame(width: actualSize, height: actualSize)
            .blur(radius: style.blobBlur)
            .scaleEffect(scale)
            .opacity(blobOpacity)
            .position(x: center.x + dx, y: center.y + dy)
            .blendMode(.plusLighter)
    }

    /// Per-frame colour for one centre blob. Pulled out of the ViewBuilder
    /// because if/else at function-body level confuses the builder.
    private func blobColor(index: Int, baseAngle: Double, progress: Double) -> Color {
        let target = palette.palette[index % palette.palette.count]
        guard style.directionalColor else { return target.color }
        let edge = palette.edgeColor(at: baseAngle)
        return RGB.lerp(edge, target, t: smoothstep(progress)).color
    }

    /// An edge-origin blob: born on the cover's perimeter (not at its centre),
    /// drifting outward toward a screen edge. Like the centre blobs, its
    /// starting colour matches the cover's edge tint at its emergence
    /// angle, transitioning toward a palette colour as it drifts.
    @ViewBuilder
    private func edgeBlob(at index: Int, time: TimeInterval, center: CGPoint, fadeIn: Double) -> some View {
        let lifetime = reduceMotion ? edgeReducedLifetime : edgeLifetime
        let phaseOffset = Double(index) * (lifetime / Double(style.edgeBlobCount))
        let cycleTime = (time + phaseOffset).truncatingRemainder(dividingBy: lifetime)
        let progress = cycleTime / lifetime

        let baseAngle = Double(index) * (2 * .pi / Double(style.edgeBlobCount))
                        + .pi / Double(style.edgeBlobCount * 2) // offset from centre blobs
        let angle = baseAngle

        let startDist = style.coverHalfExtent
        let endDist = startDist + 500
        let dist = startDist + progress * (endDist - startDist)
        let dx = cos(angle) * dist
        let dy = sin(angle) * dist

        let scale = 0.65 + 0.35 * progress
        let blobOpacity = sin(progress * .pi) * 0.55 * fadeIn

        let edgeColour = palette.edgeColor(at: angle)
        let targetColour = palette.palette[(index + 1) % palette.palette.count]
        let renderedColour = RGB.lerp(edgeColour, targetColour, t: smoothstep(progress))

        let sizeMult = sizeMultiplier(forIndex: index + 10, count: style.edgeBlobCount)
        let actualSize: CGFloat = 560 * sizeMult

        Circle()
            .fill(renderedColour.color)
            .frame(width: actualSize, height: actualSize)
            .blur(radius: 85)
            .scaleEffect(scale)
            .opacity(blobOpacity)
            .position(x: center.x + dx, y: center.y + dy)
            .blendMode(.plusLighter)
    }

    // MARK: - Math helpers

    /// Classic smoothstep, 3t² − 2t³. Used to interpolate colour so the
    /// transition reads as a smooth shift rather than a linear ramp.
    private func smoothstep(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Deterministic per-blob size variation. Hashes the index with a prime
    /// stride so adjacent blobs differ noticeably; outputs in 0.75...1.25
    /// so the overall coverage stays the same on average.
    private func sizeMultiplier(forIndex index: Int, count: Int) -> CGFloat {
        let hashed = Double((index &* 73 &+ 11) % 100) / 100.0 // 0..1
        return 0.75 + CGFloat(hashed) * 0.50
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HaloView(
            palette: CoverPalette(
                palette: [
                    RGB(r: 0.9, g: 0.4, b: 0.2),
                    RGB(r: 0.3, g: 0.5, b: 0.9),
                    RGB(r: 0.8, g: 0.7, b: 0.2),
                ],
                edges: [
                    RGB(r: 0.2, g: 0.6, b: 0.9), // right: light blue
                    RGB(r: 0.9, g: 0.4, b: 0.6), // bottom: pink
                    RGB(r: 0.2, g: 0.2, b: 0.7), // left: dark blue
                    RGB(r: 0.6, g: 0.3, b: 0.8), // top: purple
                ]
            ),
            isEngaged: true,
            style: .rich
        )
        Rectangle()
            .fill(Color.gray)
            .frame(width: 820, height: 820)
    }
}

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
