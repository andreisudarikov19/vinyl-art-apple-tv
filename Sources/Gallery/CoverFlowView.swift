import Nuke
import NukeUI
import SwiftUI

/// Classic Cover Flow browse mode: a 3D carousel of album covers with mirror
/// reflections over black, with a soft radial glow tinted by the centered
/// cover. The whole view is one focusable control — left/right move through
/// covers, center-click opens the record. Only a window of covers around the
/// selection renders, so it scales to large collections.
struct CoverFlowView: View {
    let releases: [CachedRelease]
    var onOpen: (CachedRelease) -> Void
    /// Called on swipe-up. This view's onMoveCommand consumes the up gesture,
    /// so the parent uses this to move focus to the toolbar explicitly.
    var onMoveUp: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0
    @State private var glowColor: Color = Color(white: 0.15)
    @State private var didGrabInitialFocus = false
    @FocusState private var focused: Bool

    // Tuning knobs
    // Cover size is ~57% of a 1080p TV's vertical resolution so the centered
    // cover reads as the room's focal point on a real screen (460pt looked
    // small on hardware even though it filled the simulator nicely).
    private let coverSize: CGFloat = 620
    private let windowRadius = 6
    private let sideAngle: Double = 58
    private let sideScale: CGFloat = 0.84

    var body: some View {
        Button {
            if releases.indices.contains(selectedIndex) {
                onOpen(releases[selectedIndex])
            }
        } label: {
            ZStack {
                background
                if releases.isEmpty {
                    Text("No matches")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    flow
                    VStack {
                        Spacer()
                        metadata
                            .padding(.bottom, 70)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PlainNoFocusStyle())
        .focusEffectDisabled()
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left: move(-1)
            case .right: move(1)
            case .up: onMoveUp() // onMoveCommand consumes up; hand focus to the toolbar
            default: break
            }
        }
        // Grab focus only on the first appearance — not when the view
        // re-appears after a toolbar menu closes (that would steal focus back
        // from the toolbar). View identity changes on sort/filter, re-arming it.
        .onAppear {
            guard !didGrabInitialFocus else { return }
            didGrabInitialFocus = true
            focused = true
        }
        .task(id: selectedIndex) { await updateGlow() }
    }

    // MARK: - Pieces

    private var background: some View {
        CollectionGlowBackground(glowColor: glowColor, reference: coverSize)
    }

    private var flow: some View {
        ZStack {
            ForEach(visibleIndices, id: \.self) { index in
                let d = index - selectedIndex
                CoverFlowCard(release: releases[index], coverSize: coverSize, prominent: d == 0)
                    .scaleEffect(d == 0 ? 1 : sideScale)
                    .rotation3DEffect(
                        .degrees(rotation(for: d)),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .center,
                        perspective: 0.55
                    )
                    .offset(x: xOffset(for: d))
                    .zIndex(Double(-abs(d)))
                    .opacity(opacity(for: d))
            }
        }
        .offset(y: -40)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: selectedIndex)
    }

    private var metadata: some View {
        VStack(spacing: 8) {
            Text(current?.artistDisplayName ?? "")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            Text(current?.title ?? "")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 80)
    }

    // MARK: - Layout math

    private var visibleIndices: [Int] {
        let lo = max(0, selectedIndex - windowRadius)
        let hi = min(releases.count - 1, selectedIndex + windowRadius)
        return lo <= hi ? Array(lo...hi) : []
    }

    private var current: CachedRelease? {
        guard releases.indices.contains(selectedIndex) else { return nil }
        return releases[selectedIndex]
    }

    private func rotation(for d: Int) -> Double {
        d == 0 ? 0 : (d > 0 ? -sideAngle : sideAngle)
    }

    private func xOffset(for d: Int) -> CGFloat {
        guard d != 0 else { return 0 }
        let centerGap = coverSize * 0.60
        let sideStep = coverSize * 0.26
        let magnitude = centerGap + CGFloat(abs(d) - 1) * sideStep
        return d > 0 ? magnitude : -magnitude
    }

    private func opacity(for d: Int) -> Double {
        let fadeFrom = windowRadius - 2
        guard abs(d) > fadeFrom else { return 1 }
        let extra = Double(abs(d) - fadeFrom)
        return max(0.15, 1 - extra * 0.4)
    }

    // MARK: - Behavior

    private func move(_ delta: Int) {
        let next = max(0, min(releases.count - 1, selectedIndex + delta))
        guard next != selectedIndex else { return }
        selectedIndex = next
    }

    private func updateGlow() async {
        guard let url = current?.preferredCoverURL else { return }
        if let image = try? await ImagePipeline.shared.image(for: url) {
            glowColor = CoverColor.dominant(from: image, releaseId: current?.releaseId ?? 0)
        }
    }
}

/// A single Cover Flow card: the cover with a faded mirror reflection beneath.
private struct CoverFlowCard: View {
    let release: CachedRelease
    let coverSize: CGFloat
    let prominent: Bool

    var body: some View {
        VStack(spacing: 0) {
            coverImage
                .shadow(color: .black.opacity(0.55), radius: prominent ? 32 : 14, y: 14)
            coverImage
                .scaleEffect(x: 1, y: -1)
                .frame(width: coverSize, height: coverSize / 6, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.4), location: 0),
                            .init(color: .clear, location: 0.95),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var coverImage: some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .frame(width: coverSize, height: coverSize)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Renders only the label — no focus ring or scale. The Cover Flow is one
/// full-screen control, so any default focus chrome just frames the screen.
private struct PlainNoFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
