import Foundation

/// The geometry of the cover view's halo at one moment: what to draw, not how.
///
/// Three layers, combined with a *screen* blend (never added), bottom to top:
///
/// 1. **Rim.** Light hugging the sleeve on all four sides. At a point `d`
///    points outside the sleeve's rectangle its opacity is
///    `exp(-(d / rimDepth)²) × rimLevel(t) × rimStrength`. Its colour is
///    `palette.edgeColour(at:)` for the direction of that point from the
///    screen centre, so each side glows in the colour of the edge it leaves.
/// 2. **Aura.** The same falloff with `auraDepth`, at `auraStrength`, in the
///    palette's main colour. It keeps every part of the screen faintly lit.
/// 3. **Patches.** `patches(at:palette:)`: soft discs drifting outward.
///
/// Over the result goes a fine monochrome grain (about 0.8% of full scale)
/// to hide banding, then the dark seat and the sleeve. See
/// design-handoff/specs/05-cover-view-and-halo.md.
///
/// Port of design-handoff/reference-python/halo_reference.py. Keep the two in step.
enum HaloField {
    static let goldenRatio = 0.6180339887498949

    static let rimDepth = 170.0
    static let rimStrength = 0.9
    static let rimBreathPeriod = 40.0
    static let auraDepth = 420.0
    static let auraStrength = 0.34

    static let patchCount = 7
    /// Seconds from a patch's birth to its fade.
    static let patchLifetime = 30.0
    /// Seconds for the whole field to turn once.
    static let fieldTurn = 240.0
    static let patchStart = 300.0
    static let patchTravel = 560.0
    static let patchStrength = 0.62
    /// Gaussian sigma of a patch's soft edge, in points.
    static let patchBlur = 150.0

    struct Patch: Equatable, Sendable {
        /// Offset of the centre from the screen centre, in points.
        var dx: Double
        var dy: Double
        /// Radius of the disc before its edge is blurred by `patchBlur`.
        var radius: Double
        var opacity: Double
        var colour: OKLab
        /// 0 at birth, 1 at fade.
        var progress: Double
    }

    /// Opacity multiplier of the rim at `time`, before `rimStrength`.
    static func rimLevel(at time: TimeInterval) -> Double {
        0.5 + 0.08 * sin(time * 2 * .pi / rimBreathPeriod)
    }

    /// The drifting patches at `time` seconds. Directions and timings are
    /// spread by the golden ratio, so no two neighbours follow each other
    /// round the sleeve and no side is left dark.
    static func patches(at time: TimeInterval, palette: HaloPalette) -> [Patch] {
        (0..<patchCount).map { i in
            let index = Double(i)
            let progress = (time / patchLifetime + index * goldenRatio).truncatingRemainder(dividingBy: 1)
            let angle = index * 2 * .pi * goldenRatio + time * 2 * .pi / fieldTurn
            let distance = patchStart + progress * patchTravel
            let size = 380 + 160 * (Double((i * 73 + 11) % 100) / 100)
            let colour = OKLab.lerp(
                palette.edgeColour(at: angle),
                palette.colours[i % 3],
                t: smoothstep(progress)
            )
            return Patch(
                dx: cos(angle) * distance,
                dy: sin(angle) * distance,
                radius: size * (0.8 + 0.4 * progress) * 0.55,
                opacity: pow(max(0, sin(progress * .pi)), 1.5) * patchStrength,
                colour: colour,
                progress: progress
            )
        }
    }

    /// How much of a patch is left `distance` points from its centre, before
    /// the patch's own opacity: a disc of `radius` whose edge is blurred by
    /// `patchBlur`. 1 well inside, a half on the disc's edge, 0 well outside.
    static func patchEdge(distance: Double, radius: Double) -> Double {
        0.5 * erfc((distance - radius) / (2.0.squareRoot() * patchBlur))
    }

    /// How far from its centre a patch is drawn: three blurs past its edge,
    /// where a thousandth of it is left.
    static func patchReach(radius: Double) -> Double {
        radius + 3 * patchBlur
    }

    static func smoothstep(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }
}
