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
    @FocusState private var discogsNoticeFocused: Bool
    @State private var glowColor: Color = Color(white: 0.15)
    @State private var trampolineArmed: Bool = true
    @State private var showingDiscogsQR = false
    /// The tile whose caption was entered last. Its release is the one the
    /// Discogs QR shows, and the lens stays on it while focus is on the caption.
    @State private var lensID: Int?

    // Tuning knobs
    private let columnCount = 7
    private let gutter: CGFloat = 2
    private let bezel: CGFloat = 14
    private let titleGap: CGFloat = 8
    private let titleAreaHeight: CGFloat = 56
    private let captionAreaHeight: CGFloat = 40

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gutter), count: columnCount)
    }

    /// The tile the lens is drawn on: the focused tile, or the tile whose
    /// caption has focus. Nil when focus is elsewhere (the toolbar).
    private var lensTileID: Int? {
        focusedID ?? (discogsNoticeFocused ? lensID : nil)
    }

    private var lensRelease: CachedRelease? {
        guard let lensTileID else { return nil }
        return releases.first { $0.releaseId == lensTileID }
    }

    private func isLensTile(_ release: CachedRelease) -> Bool {
        lensTileID == release.releaseId
    }

    /// Height of everything under the cover in the lens, so the cover stays on its cell.
    private var belowCoverHeight: CGFloat {
        titleGap + titleAreaHeight + titleGap + captionAreaHeight
    }

    private var currentDiscogsURL: String? {
        lensID.map { DiscogsNotice.releasePageURL(releaseId: $0) }
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
                }
                .padding(.top, 150) // clear the floating toolbar
                .padding(.bottom, 140)
                .overlayPreferenceValue(FocusedTileBounds.self) { anchor in
                    GeometryReader { proxy in
                        if let anchor, let release = lensRelease {
                            let rect = proxy[anchor]
                            let scale: CGFloat = reduceMotion ? 1 : 1.18
                            lens(release, coverSize: rect.size)
                                .scaleEffect(scale)
                                // Shift down so the COVER (not the whole lens, which
                                // includes the title and caption below) stays aligned with the cell.
                                .position(x: rect.midX, y: rect.midY + belowCoverHeight / 2 * scale)
                                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: lensTileID)
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
        // Menu on the remote dismisses the QR cover; focus goes back to the caption.
        .fullScreenCover(isPresented: $showingDiscogsQR, onDismiss: { discogsNoticeFocused = true }) {
            if let url = currentDiscogsURL {
                DiscogsReleaseQRView(url: url)
            }
        }
        .task(id: lensTileID) { await updateGlow() }
    }

    private func updateGlow() async {
        guard let url = lensRelease?.preferredCoverURL else { return }
        if let image = try? await ImagePipeline.shared.image(for: url) {
            glowColor = CoverColor.dominant(from: image, releaseId: lensRelease?.releaseId ?? 0)
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
                    isLensTile(release) ? $0 : nil
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
            // The caption sits under the lens, so down goes to it first; its
            // own down then moves on to the tile below.
            lensID = releases[index].releaseId
            discogsNoticeFocused = true
        @unknown default:
            break
        }
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
    /// holds the title and the Discogs caption beneath it, and refracts the
    /// surrounding covers.
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
            discogsCaption
                .frame(height: captionAreaHeight)
        }
        .padding(bezel)
        .glassBezel()
        .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
    }

    /// The Discogs caption under the lens title, the same as on the record
    /// screen and CoverFlow. Selecting it shows a QR code of the lens release's
    /// discogs.com page. Down from a tile lands here, up returns to that tile,
    /// and down again goes to the tile below.
    private var discogsCaption: some View {
        Button {
            showingDiscogsQR = true
        } label: {
            DiscogsNoticeLabel()
        }
        .buttonStyle(DiscogsNoticeButtonStyle())
        // Turns off tvOS's system focus block so only the label's own pill shows.
        .focusEffectDisabled()
        .focused($discogsNoticeFocused)
        // Other directions are consumed so focus stays on the caption.
        .onMoveCommand { direction in
            guard let lensID, let index = releases.firstIndex(where: { $0.releaseId == lensID }) else { return }
            switch direction {
            case .up:
                focusedID = lensID
            case .down:
                let below = index + columnCount
                if below < releases.count { focusedID = releases[below].releaseId }
            default:
                break
            }
        }
        .accessibilityHint("Shows a QR code for this release on discogs.com.")
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
