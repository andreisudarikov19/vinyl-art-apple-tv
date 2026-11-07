import SwiftUI

/// Shared collection backdrop: black with a soft radial glow tinted by the
/// in-focus cover's dominant colour. Both browse modes (CoverFlow and the
/// mosaic grid) use it so they share one background, and the glow cross-fades
/// as the focused colour changes.
struct CollectionGlowBackground: View {
    var glowColor: Color
    /// Reference size that scales the glow: strongest within 0.4× this size,
    /// fading to nothing at 2.2×. CoverFlow passes its cover size (620 pt) and
    /// AboutView passes 700. The mosaic grid takes this 460 pt default, which
    /// was CoverFlow's cover size before the covers grew to 620 pt, so the
    /// mosaic's glow is now about three-quarters the size of CoverFlow's.
    var reference: CGFloat = 460

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [glowColor.opacity(0.7), glowColor.opacity(0.28), .clear],
                center: .center,
                startRadius: reference * 0.4,
                endRadius: reference * 2.2
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: glowColor)
    }
}
