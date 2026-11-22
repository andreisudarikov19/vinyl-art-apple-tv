import SwiftUI

/// The scale's idle look, shared by every style (spec 01, "When the Gallery
/// is idle"; ScaleA.jpg and GalleryIdle.jpg). While the ambient halo is on,
/// the tape fades down, the reading drops to 70% and the count is hidden.
/// The needle alone stays lit, and a warm glow comes up around it
/// (`ScaleNeedleGlow`), as if it carried the light.
enum ScaleIdleLook {
    /// Brightness of the tape (ticks and labels) when idle.
    static let tape = 0.3
    /// Brightness of the reading when idle.
    static let reading = 0.7
    /// Brightness of the needle when idle: it stays fully lit.
    static let needle = 1.0
    /// Brightness of the count, which sits in the scale's box: hidden when
    /// idle, as in GalleryIdle.jpg. It returns with the first press.
    static let count = 0.0
    /// Strength of the needle's own tight glow when idle, against 1 in use.
    /// The wide idle glow around it is `ScaleNeedleGlow`.
    static let glow = 1.0

    /// The opacity of something that is `level` bright when idle and full
    /// bright in use. `idle` is 0 in use and 1 when the halo is on.
    static func opacity(idleLevel level: Double, idle: Double) -> Double {
        1 - (1 - level) * idle
    }

    /// Idle also draws the tape in toward the needle (GalleryIdle.jpg): it
    /// is gone within 20% of the box's width from either end and whole from
    /// 42%, so its two ends fade into the ground and only the middle is left.
    static let drawnInStart = 0.2
    static let drawnInEnd = 0.42

    /// How much of a tick or label at `x` in a box `width` wide is left:
    /// 1 everywhere in use, and the drawn-in fade when idle.
    static func tapeReach(at x: Double, width: Double, idle: Double) -> Double {
        guard width > 0 else { return 1 }
        let fromEnd = min(x, width - x) / width
        let drawnIn = min(1, max(0, (fromEnd - drawnInStart) / (drawnInEnd - drawnInStart)))
        return 1 - (1 - drawnIn) * idle
    }
}

/// How tall and how bright a tick is, shared by every style (spec 01).
/// Only a group that carries a label gets the tall white tick; a group whose
/// label was skipped gets a middle one, so every tall tick can be read.
struct ScaleTickLook: Equatable, Sendable {
    let height: CGFloat
    let opacity: Double

    init(_ tick: ScaleTape.Tick) {
        switch tick {
        case .record:
            height = 12
            opacity = 0.4
        case .group:
            height = 18
            opacity = 0.7
        case .labelledGroup:
            height = 24
            opacity = 1
        }
    }
}

/// The needle's mood light, for every scale style. While the ambient halo is
/// on and the tape is dim, the needle glows like a candle: a small bright
/// core at the needle, a soft halo close around it, and a wide, faint spread
/// of deeper amber that carries well past the scale. Each ring is fainter and
/// warmer than the one inside it. It comes up slowly with the halo and goes
/// out quickly with the first press. Only the needle glows; the reading above
/// it has no light of its own.
///
/// It is a view of its own, not part of the scale's canvas, because a canvas
/// cuts its drawing off at its edges and the light has to spill past the
/// 72 pt box. Place it in the scale's box, under the needle's drawing.
struct ScaleNeedleGlow: View {
    /// The ambient halo is on.
    let idle: Bool

    /// The halo close to the needle: a warmer yellow than the needle's yolk.
    private static let warm = Color(hex: 0xFFAE3D)
    /// The far spread: deeper amber, as a candle's light reddens with distance.
    private static let amber = Color(hex: 0xFF9430)
    /// The needle runs from 40 pt to the bottom of the 72 pt box, so its
    /// middle is 20 pt below the box's.
    private static let needleCentre: CGFloat = 20

    var body: some View {
        ZStack {
            // The spread: wide and faint.
            Ellipse()
                .fill(Self.amber)
                .frame(width: 300, height: 170)
                .blur(radius: 60)
                .opacity(0.2)
            // The halo close around the needle.
            Ellipse()
                .fill(Self.warm)
                .frame(width: 110, height: 84)
                .blur(radius: 26)
                .opacity(0.22)
            // The core, hugging the needle.
            Capsule()
                .fill(Theme.yolk)
                .frame(width: 12, height: 42)
                .blur(radius: 8)
                .opacity(0.7)
        }
        .offset(y: Self.needleCentre)
        .opacity(idle ? 1 : 0)
        .animation(.easeInOut(duration: idle ? 2.5 : 0.4), value: idle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
