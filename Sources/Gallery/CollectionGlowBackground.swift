import SwiftUI

/// Shared collection backdrop: black with a soft radial glow tinted by the
/// in-focus cover's dominant colour. Both browse modes (CoverFlow and the
/// mosaic grid) use it so they share one background, and the glow cross-fades
/// as the focused colour changes.
struct CollectionGlowBackground: View {
    var glowColor: Color
    /// Reference size that sets the glow radius — defaults to the CoverFlow
    /// cover size so the glow geometry is identical across both modes.
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
