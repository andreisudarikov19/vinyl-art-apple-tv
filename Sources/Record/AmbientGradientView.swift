import SwiftUI

/// Slowly-shifting mesh gradient seeded from the cover's colors, behind the
/// cover-focused view. Holds still when Reduce Motion is on.
struct AmbientGradientView: View {
    let imageURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: [Color] = AmbientGradientView.fallback

    private static let fallback: [Color] = [
        Color(white: 0.10), Color(white: 0.16), Color(white: 0.06),
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: points(at: t),
                colors: meshColors
            )
            .ignoresSafeArea()
        }
        .task(id: imageURL) {
            guard let imageURL else { return }
            let extracted = await DominantColors.extract(from: imageURL)
            if !extracted.isEmpty { palette = extracted }
        }
    }

    /// Nine colors for the 3×3 mesh, cycling the extracted palette and
    /// darkening for an ambient backdrop.
    private var meshColors: [Color] {
        (0..<9).map { index in
            palette[index % palette.count].opacity(0.85)
        }
    }

    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.3) * 0.12)
        let b = Float(cos(t * 0.23) * 0.12)
        return [
            [0, 0], [0.5 + a * 0.3, 0], [1, 0],
            [0, 0.5 + b * 0.3], [0.5 + a, 0.5 + b], [1, 0.5 - b * 0.3],
            [0, 1], [0.5 - a * 0.3, 1], [1, 1],
        ]
    }
}
