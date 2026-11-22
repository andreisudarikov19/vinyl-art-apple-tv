import SwiftUI
import UIKit

/// RGB triplet in 0...1 space. Used by the halo to interpolate between
/// colours per-frame without paying the cost of `UIColor(Color(...))` round
/// trips inside the render loop.
struct RGB: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    /// Linear interpolation. `t` is clamped to 0...1.
    static func lerp(_ a: RGB, _ b: RGB, t: Double) -> RGB {
        let clamped = max(0, min(1, t))
        return RGB(
            r: a.r + (b.r - a.r) * clamped,
            g: a.g + (b.g - a.g) * clamped,
            b: a.b + (b.b - a.b) * clamped
        )
    }
}
