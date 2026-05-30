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
                ZStack {
                    if style.ambientBase {
                        ambientBase(time: t)
                    }
                    ForEach(0..<style.blobCount, id: \.self) { index in
                        centerBlob(at: index, time: t, center: center)
                    }
                    if let edgeStart = style.edgeBlobsAfter,
                       elapsedEngaged >= edgeStart {
                        let fadeIn = min(1.0, (elapsedEngaged - edgeStart) / edgeFadeInSeconds)
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
            renderedOpacity = isEngaged ? 1 : 0
            if isEngaged { engagedAt = Date() }
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
    private func centerBlob(at index: Int, time: TimeInterval, center: CGPoint) -> some View {
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

        let blobOpacity = sin(progress * .pi) * 0.85

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
