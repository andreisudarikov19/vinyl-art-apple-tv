import Foundation

/// The scale's idle look, shared by every style (spec 01, "When the Gallery
/// is idle"; ScaleA.jpg and GalleryIdle.jpg). While the ambient halo is on,
/// the tape fades down, the reading and the needle drop to 70%, the needle's
/// glow is halved, and the count drops with the reading.
enum ScaleIdleLook {
    /// Brightness of the tape (ticks and labels) when idle.
    static let tape = 0.3
    /// Brightness of the reading, and of the needle, when idle.
    static let reading = 0.7
    static let needle = 0.7
    /// Brightness of the count, which sits in the scale's box.
    static let count = 0.7
    /// Strength of the needle's glow when idle, against 1 in use.
    static let glow = 0.5

    /// The opacity of something that is `level` bright when idle and full
    /// bright in use. `idle` is 0 in use and 1 when the halo is on.
    static func opacity(idleLevel level: Double, idle: Double) -> Double {
        1 - (1 - level) * idle
    }
}
