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
    /// Called when focus tries to leave the top row of tiles upward. The
    /// parent uses this to move focus to the toolbar — the focus engine
    /// doesn't reliably step out of the grid into the toolbar on its own.
    var onMoveUp: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedID: Int?
    @FocusState private var trampolineFocused: Bool
    @State private var glowColor: Color = Color(white: 0.15)
    @State private var trampolineArmed: Bool = true
    @State private var viewportSize: CGSize = .zero

    // Tuning knobs
    private let columnCount = 7
    private let gutter: CGFloat = 2
    private let topInset: CGFloat = 150 // clears the floating toolbar
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

    /// Empty positions of the mosaic, out to the bottom of the screen. Each is
    /// filled by a placeholder cell the size of a cover. They are not in
    /// `releases`, so focus movement, which steps through `releases`, skips them.
    private var placeholders: [MosaicPlaceholderLayout.Position] {
        // Cover side as the flexible columns lay it out: the width less the
        // gutters between columns, divided by the column count.
        let side = viewportSize.width > 0
            ? (viewportSize.width - gutter * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            : 0
        let rows = MosaicPlaceholderLayout.rowCountFillingViewport(
            albumCount: releases.count,
            columnCount: columnCount,
            pitch: side > 0 ? side + gutter : 0,
            viewportHeight: viewportSize.height,
            topInset: topInset
        )
        return MosaicPlaceholderLayout.emptyPositions(
            albumCount: releases.count,
            columnCount: columnCount,
            rowCount: rows
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Same backdrop as CoverFlow: black with a soft glow tinted by the
            // focused cover, so the empty top/bottom of the wall isn't dead black.
            CollectionGlowBackground(glowColor: glowColor)
            ScrollView {
                LazyVGrid(columns: columns, spacing: gutter) {
                    ForEach(Array(releases.enumerated()), id: \.element.releaseId) { index, release in
                        tile(release, at: index)
                    }
                    ForEach(placeholders, id: \.self) { position in
                        placeholder(at: position)
                    }
                }
                .padding(.top, topInset)
                .padding(.bottom, 140)
                // Lines beneath the covers: they show through the gutters and
                // the placeholders. The overlay repeats them above the covers.
                // Both live in the scroll content, so they move with the grid.
                .background(MosaicLines(columnCount: columnCount, gutter: gutter, topInset: topInset))
                .overlay(MosaicLines(columnCount: columnCount, gutter: gutter, topInset: topInset))
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
            // Focus trampoline: an invisible focusable strip occupying the gap
            // between the floating toolbar and the first row of tiles. The
            // tvOS focus engine doesn't reliably step focus from the toolbar
            // into the dense grid of small tile buttons inside a ScrollView,
            // so we give it a single, large, geometrically adjacent target
            // here and redirect to the first tile once focus arrives. The
            // strip is fully REMOVED from the hierarchy once a tile is
            // focused (not just disabled) so it can't act as a focus barrier
            // when the user later moves up from the grid back to the toolbar.
            if trampolineArmed {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding(.top, 100)
                    .focusable()
                    .focused($trampolineFocused)
                    .focusEffectDisabled()
                    .onChange(of: trampolineFocused) { _, focused in
                        guard focused, let first = releases.first?.releaseId else { return }
                        focusedID = first
                        trampolineArmed = false
                    }
            }
        }
        .onChange(of: focusedID) { _, new in
            // When focus has left the grid (back up to the toolbar), re-arm
            // the trampoline so the next down-press is caught again.
            if new == nil { trampolineArmed = true }
        }
        // Edge-to-edge: drop the safe-area (overscan) inset so the wall fills
        // the full screen width.
        .ignoresSafeArea(.container, edges: .horizontal)
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { viewportSize = $0 })
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
    private func tile(_ release: CachedRelease, at index: Int) -> some View {
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
        .accessibilityLabel(release.galleryAccessibilityLabel)
        // The focus engine doesn't reliably step focus out of these tiles to
        // the toolbar above, and onMoveCommand consumes all directions, so
        // each tile drives its own navigation: arithmetic for in-grid moves,
        // a callback to the parent for escaping upward to the toolbar.
        .onMoveCommand { direction in
            move(from: index, direction: direction)
        }
    }

    private func move(from index: Int, direction: MoveCommandDirection) {
        let col = index % columnCount
        let count = releases.count
        switch direction {
        case .left:
            if col > 0 { focusedID = releases[index - 1].releaseId }
        case .right:
            if col + 1 < columnCount, index + 1 < count {
                focusedID = releases[index + 1].releaseId
            }
        case .up:
            let above = index - columnCount
            if above >= 0 {
                focusedID = releases[above].releaseId
            } else {
                onMoveUp() // escape to the toolbar
            }
        case .down:
            let below = index + columnCount
            if below < count { focusedID = releases[below].releaseId }
        @unknown default:
            break
        }
    }

    /// An empty position: a cover-sized cell that takes no input and no focus.
    /// Its tick, in the tuner's style, sits on the gutter below it, alternating
    /// by grid position so the placeholders read as a checkerboard.
    private func placeholder(at position: MosaicPlaceholderLayout.Position) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if (position.row + position.column).isMultiple(of: 2) {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: 8)
                        .offset(y: 5)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// The mosaic's hairlines in the radio tuner's style: white at 18% opacity,
/// 1 pt, running down the gutters between the cover cells. The gutter is 2 pt,
/// so a 1 pt line sits centred in it.
private struct MosaicLines: View {
    let columnCount: Int
    let gutter: CGFloat
    let topInset: CGFloat

    var body: some View {
        Canvas { context, size in
            let side = (size.width - gutter * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            let pitch = side + gutter
            guard pitch > 0 else { return }
            var path = Path()
            for column in 1..<columnCount {
                let x = CGFloat(column) * pitch - gutter / 2
                path.move(to: CGPoint(x: x, y: topInset))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            let rows = Int((size.height - topInset) / pitch) + 1
            for row in stride(from: 1, through: max(rows, 1), by: 1) {
                let y = topInset + CGFloat(row) * pitch - gutter / 2
                guard y < size.height else { break }
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
        .allowsHitTesting(false)
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
