import Foundation

/// The ambient effect of the Gallery and the track list: the sleeve's colour
/// swells out and draws back, slowly. No patches and no rim; the lava-lamp
/// halo belongs to the cover view alone.
///
/// Port of design-handoff/reference-python/halo_reference.py. Keep the two in step.
enum Tide {
    /// Seconds for one cycle: 45 coming in, 45 going out.
    static let period = 90.0
    static let lapPeriod = 8.0
    /// The lapping, as a share of the full reach.
    static let lap = 0.04

    /// 0 at low tide, 1 at high tide. `running` is how long the tide has
    /// been moving, in seconds; it stops counting while the tide is held.
    static func reach(running: TimeInterval) -> Double {
        let swell = 0.5 - 0.5 * cos(running * 2 * .pi / period)
        return min(1, max(0, swell + lap * sin(running * 2 * .pi / lapPeriod)))
    }

    /// Where the tint stands under Reduce Motion.
    static let reducedMotionReach = 0.5
}
