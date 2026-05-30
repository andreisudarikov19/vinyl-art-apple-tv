import SwiftUI

/// Cover-derived ambient halo: 4 heavily-blurred colour blobs born small at
/// the view's centre (behind the album cover) and slowly drifting outward in
/// staggered directions. Each blob carries one of the album's palette colours
/// and the four are out-of-phase so coverage is continuous. Composited with
/// `.plusLighter` so where they overlap, colours bloom into one another.
///
/// The cover is meant to be drawn on top of this view in the parent ZStack —
/// blobs only become visible as they emerge past the cover's silhouette, which
/// is the whole "halo emanating from behind the record" reading.
struct HaloView: View {
    let palette: CoverPalette
    let isEngaged: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renderedOpacity: Double = 0

    // Tuning knobs
    private let blobCount = 4
    private let blobSize: CGFloat = 700
    private let blobBlur: CGFloat = 100
    private let maxDriftDistance: Double = 700
    private let liveLifetime: Double = 18 // seconds for one outward cycle
    private let reducedLifetime: Double = 32
    private let fadeInSeconds: Double = 3
    private let fadeOutSeconds: Double = 0.4

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // Cap at 30fps — the motion is intentionally slow, no need to burn
            // 60fps on Apple TV HD.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<blobCount, id: \.self) { index in
                        blob(at: index, time: t, center: center)
                    }
                }
            }
        }
        .opacity(renderedOpacity)
        .allowsHitTesting(false)
        .onAppear {
            // Match initial opacity to engagement so the view doesn't pop in
            // when added to the hierarchy with isEngaged already true.
            renderedOpacity = isEngaged ? 1 : 0
        }
        .onChange(of: isEngaged) { _, new in
            // Fade-in is slow and ambient; fade-out is snappy so user input
            // gets immediate visual acknowledgement.
            withAnimation(.easeInOut(duration: new ? fadeInSeconds : fadeOutSeconds)) {
                renderedOpacity = new ? 1 : 0
            }
        }
    }

    /// One blob's geometry at the current moment. Each blob has its own base
    /// angle (evenly spaced around the cover) and its own phase offset so the
    /// four are staggered through their lifecycle — at any instant one is
    /// being born, one is at peak, one is fading, one is mid-drift.
    @ViewBuilder
    private func blob(at index: Int, time: TimeInterval, center: CGPoint) -> some View {
        let color = palette.colors[index % palette.colors.count]
        let lifetime = reduceMotion ? reducedLifetime : liveLifetime
        let phaseOffset = Double(index) * (lifetime / Double(blobCount))
        let cycleTime = (time + phaseOffset).truncatingRemainder(dividingBy: lifetime)
        let progress = cycleTime / lifetime // 0...1

        let baseAngle = Double(index) * (2 * .pi / Double(blobCount))
        // Subtle low-frequency wandering of the drift angle so successive cycles
        // of the same blob don't trace identical paths. Skipped in Reduce Motion.
        let angleWobble = reduceMotion ? 0 : sin(time / 11.0) * 0.25
        let angle = baseAngle + angleWobble
        let distance = progress * maxDriftDistance
        let dx = cos(angle) * distance
        let dy = sin(angle) * distance

        // Grow from 0.5x (hidden behind cover) to 1.1x as the blob travels.
        let scaleBase = 0.5 + 0.6 * progress
        // Perlin-ish pulse: small periodic scale modulation per blob, out of
        // phase with neighbours so the breathing isn't synchronised.
        let pulse = reduceMotion ? 0 : sin(time * 1.3 + Double(index) * 0.7) * 0.10
        let scale = scaleBase + pulse

        // Sine envelope: 0 at birth, peak in middle, 0 at end of cycle.
        // 0.85 cap so blobs don't overpower the cover when stacked.
        let blobOpacity = sin(progress * .pi) * 0.85

        Circle()
            .fill(color)
            .frame(width: blobSize, height: blobSize)
            .blur(radius: blobBlur)
            .scaleEffect(scale)
            .opacity(blobOpacity)
            .position(x: center.x + dx, y: center.y + dy)
            .blendMode(.plusLighter)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        HaloView(
            palette: CoverPalette(colors: [
                Color(red: 0.9, green: 0.4, blue: 0.2),
                Color(red: 0.3, green: 0.5, blue: 0.9),
                Color(red: 0.8, green: 0.7, blue: 0.2),
            ]),
            isEngaged: true
        )
        Rectangle()
            .fill(Color.gray)
            .frame(width: 620, height: 620)
    }
}
