import Foundation

/// The scale's idle look, shared by every style (spec 01, "When the Gallery
/// is idle"; ScaleA.jpg and GalleryIdle.jpg). While the ambient halo is on,
/// the tape fades down, the reading and the needle drop to 70%, the needle's
/// glow is halved, and the count is hidden.
enum ScaleIdleLook {
    /// Brightness of the tape (ticks and labels) when idle.
    static let tape = 0.3
    /// Brightness of the reading, and of the needle, when idle.
    static let reading = 0.7
    static let needle = 0.7
    /// Brightness of the count, which sits in the scale's box: hidden when
    /// idle, as in GalleryIdle.jpg. It returns with the first press.
    static let count = 0.0
    /// Strength of the needle's glow when idle, against 1 in use.
    static let glow = 0.5

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
