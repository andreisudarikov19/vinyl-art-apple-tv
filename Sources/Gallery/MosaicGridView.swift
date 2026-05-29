import NukeUI
import SwiftUI

/// Grid browse mode as a full-color "tapestry": a dense, edge-to-edge wall of
/// sharp covers with hairline gutters. The focused cover lifts above the wall
/// inside a Liquid Glass lens/mount that holds its title and refracts the
/// neighbouring covers; the lens glides between tiles as focus moves. Falls
/// back to a frosted-material lens on tvOS 18–25.
struct MosaicGridView: View {
    let releases: [CachedRelease]
    var onOpen: (CachedRelease) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedID: Int?
    @Namespace private var lensNamespace

    // Tuning knobs
    private let columnCount = 7
    private let gutter: CGFloat = 2

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gutter), count: columnCount)
    }

    var body: some View {
        ScrollView {
            lensContainer {
                LazyVGrid(columns: columns, spacing: gutter) {
                    ForEach(releases) { release in
                        tile(release)
                    }
                }
                .padding(.top, 150) // clear the floating toolbar
                .padding(.bottom, 140)
            }
        }
        // Edge-to-edge: drop the safe-area (overscan) inset so the wall fills
        // the full screen width.
        .ignoresSafeArea(.container, edges: .horizontal)
    }

    @ViewBuilder
    private func lensContainer<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if #available(tvOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
    }

    private func tile(_ release: CachedRelease) -> some View {
        let isFocused = focusedID == release.releaseId
        return Button {
            onOpen(release)
        } label: {
            cover(release)
                .overlay(alignment: .bottom) {
                    if isFocused { titlePlate(release) }
                }
        }
        .buttonStyle(BareButtonStyle())
        .focusEffectDisabled()
        .focused($focusedID, equals: release.releaseId)
        .accessibilityLabel("\(release.artistDisplayName) – \(release.title)")
        .scaleEffect(isFocused ? 1.16 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.65 : 0), radius: isFocused ? 30 : 0, y: isFocused ? 18 : 0)
        .zIndex(isFocused ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: isFocused)
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

    /// Liquid Glass title plate over the bottom of the focused cover — frosts
    /// only that strip, refracting the art beneath the text. Glides between
    /// tiles via the shared glass id.
    private func titlePlate(_ release: CachedRelease) -> some View {
        VStack(spacing: 2) {
            Text(release.artistDisplayName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(release.title)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassPlate(id: 1, in: lensNamespace)
    }
}

/// Renders only the label — no focus platter or scale. The mosaic controls its
/// own focus visual (lift + magnify + glass plate) via focusedID.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private extension View {
    @ViewBuilder
    func glassPlate(id: Int, in namespace: Namespace.ID) -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                .glassEffectID(id, in: namespace)
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
