import Nuke
import NukeUI
import SwiftUI

/// Grid browse mode as a full-color "tapestry": a dense, edge-to-edge wall of
/// sharp covers with hairline gutters. The focused cover lifts and magnifies
/// above the wall inside a Liquid Glass bezel that holds its title and refracts
/// the neighbouring covers. The focused lens is rendered as a single overlay on
/// top of the grid (positioned at the focused cell via an anchor) so it always
/// draws above its neighbours — LazyVGrid doesn't reliably honour zIndex.
struct MosaicGridView: View {
    let releases: [CachedRelease]
    var onOpen: (CachedRelease) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedID: Int?
    @State private var glowColor: Color = Color(white: 0.15)

    // Tuning knobs
    private let columnCount = 7
    private let gutter: CGFloat = 2
    private let bezel: CGFloat = 14
    private let titleGap: CGFloat = 8
    private let titleAreaHeight: CGFloat = 56

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gutter), count: columnCount)
    }

    private var focusedRelease: CachedRelease? {
        guard let focusedID else { return nil }
        return releases.first { $0.releaseId == focusedID }
    }

    var body: some View {
        ZStack {
            // Same backdrop as CoverFlow: black with a soft glow tinted by the
            // focused cover, so the empty top/bottom of the wall isn't dead black.
            CollectionGlowBackground(glowColor: glowColor)
            ScrollView {
                LazyVGrid(columns: columns, spacing: gutter) {
                    ForEach(releases) { release in
                        tile(release)
                    }
                }
                .padding(.top, 150) // clear the floating toolbar
                .padding(.bottom, 140)
                // Group the tiles into a focus section so a "down" press from
                // the toolbar (also a focus section) sees the grid as a single
                // adjacent target, instead of struggling to pick one tile out
                // of dozens and staying trapped in the toolbar.
                .focusSection()
                .overlayPreferenceValue(FocusedTileBounds.self) { anchor in
                    GeometryReader { proxy in
                        if let anchor, let release = focusedRelease {
                            let rect = proxy[anchor]
                            let scale: CGFloat = reduceMotion ? 1 : 1.18
                            lens(release, coverSize: rect.size)
                                .scaleEffect(scale)
                                // Shift down so the COVER (not the whole lens, which
                                // includes the title below) stays aligned with the cell.
                                .position(x: rect.midX, y: rect.midY + (titleGap + titleAreaHeight) / 2 * scale)
                                .allowsHitTesting(false)
                                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: focusedID)
                        }
                    }
                }
            }
        }
        // Edge-to-edge: drop the safe-area (overscan) inset so the wall fills
        // the full screen width.
        .ignoresSafeArea(.container, edges: .horizontal)
        .task(id: focusedID) { await updateGlow() }
    }

    private func updateGlow() async {
        guard let url = focusedRelease?.preferredCoverURL else { return }
        if let image = try? await ImagePipeline.shared.image(for: url) {
            glowColor = CoverColor.dominant(from: image, releaseId: focusedRelease?.releaseId ?? 0)
        }
    }

    // Flat tile in the wall. Reports its bounds (only while focused) so the
    // overlay can draw the magnified lens at exactly this position.
    private func tile(_ release: CachedRelease) -> some View {
        Button {
            onOpen(release)
        } label: {
            cover(release)
                .anchorPreference(key: FocusedTileBounds.self, value: .bounds) {
                    focusedID == release.releaseId ? $0 : nil
                }
        }
        .buttonStyle(BareButtonStyle())
        .focusEffectDisabled()
        .focused($focusedID, equals: release.releaseId)
        .accessibilityLabel("\(release.artistDisplayName) – \(release.title)")
    }

    private func cover(_ release: CachedRelease) -> some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The magnified focused cover, crisp, set in a Liquid Glass bezel that
    /// holds the title and refracts the surrounding covers.
    private func lens(_ release: CachedRelease, coverSize: CGSize) -> some View {
        VStack(spacing: titleGap) {
            cover(release)
                .frame(width: coverSize.width, height: coverSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(spacing: 2) {
                Text(release.artistDisplayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(release.title)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: coverSize.width)
            .frame(height: titleAreaHeight)
        }
        .padding(bezel)
        .glassBezel()
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
    }
}

/// Bounds of the currently-focused tile, used to position the overlay lens.
private struct FocusedTileBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Renders only the label — no focus platter or scale. The mosaic controls its
/// own focus visual (the overlay lens) via focusedID.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private extension View {
    @ViewBuilder
    func glassBezel() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
