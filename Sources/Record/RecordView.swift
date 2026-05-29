import NukeUI
import SwiftUI

/// Loads a release's tracklist for the record screen. Injected via the
/// environment so the gallery's navigation destination stays decoupled from
/// the Discogs client.
private struct ReleaseDetailLoaderKey: EnvironmentKey {
    static let defaultValue: @Sendable (Int) async throws -> ReleaseDetail = { _ in
        throw DiscogsClientError.invalidResponse
    }
}

extension EnvironmentValues {
    var releaseDetailLoader: @Sendable (Int) async throws -> ReleaseDetail {
        get { self[ReleaseDetailLoaderKey.self] }
        set { self[ReleaseDetailLoaderKey.self] = newValue }
    }
}

/// Resolves a single release's higher-quality cover on demand (MusicBrainz +
/// Cover Art Archive), so opening a record swaps in a better cover right away
/// instead of waiting for the background sweep to reach it.
private struct CoverResolverKey: EnvironmentKey {
    static let defaultValue: @Sendable (Int) async -> Void = { _ in }
}

extension EnvironmentValues {
    var coverResolver: @Sendable (Int) async -> Void {
        get { self[CoverResolverKey.self] }
        set { self[CoverResolverKey.self] = newValue }
    }
}

struct RecordView: View {
    let release: CachedRelease

    @Environment(\.releaseDetailLoader) private var loader
    @Environment(\.coverResolver) private var resolveCover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: RecordViewModel?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel {
                interactive(viewModel)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = RecordViewModel(release: release, loadDetail: loader)
            viewModel = model
            await model.load()
        }
        .task {
            // Jump the cover-art queue for the record being viewed so a better
            // cover replaces the Discogs one immediately. Skips releases already
            // attempted (resolved or confirmed to have no Cover Art Archive art).
            guard !release.coverLookupAttempted else { return }
            await resolveCover(release.releaseId)
        }
    }

    private func interactive(_ model: RecordViewModel) -> some View {
        // The design called for a subtle haptic on each side flip, but tvOS
        // exposes no Siri Remote haptics API (no .sensoryFeedback, no usable
        // CoreHaptics hardware), so the flip is confirmed visually only: the
        // tracklist/side header update in informative view, and the side toast
        // in cover-focused view.
        Button {
            changeSide(on: model, forward: true)
        } label: {
            ZStack {
                if model.displayMode == .coverFocused {
                    coverFocusedStage(model).transition(.opacity)
                } else {
                    informativeStage(model).transition(.opacity)
                }
                toastOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The whole screen is the (only) focusable control. `.plain` +
        // focusEffectDisabled still leaves a focus ring framing the screen
        // edge on tvOS, so use a custom style that renders only the label.
        .buttonStyle(AmbientButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel("\(release.artistDisplayName), \(release.title)")
        .accessibilityHint("Swipe left or right to change sides. Swipe up for the cover, down for the tracklist.")
        .onMoveCommand { direction in
            switch direction {
            case .up: setMode(.coverFocused, on: model)
            case .down: setMode(.informative, on: model)
            case .right: changeSide(on: model, forward: true)
            case .left: changeSide(on: model, forward: false)
            default: break
            }
        }
    }

    // MARK: - Stages

    private func informativeStage(_ model: RecordViewModel) -> some View {
        HStack(alignment: .top, spacing: 100) {
            VStack(alignment: .leading, spacing: 24) {
                cover(coverSide, cornerRadius: 12, shadowRadius: 30)
                albumHeader
            }
            tracklist(model)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 100)
        .padding(.top, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(blurredBackdrop(dark: 0.5))
    }

    private func coverFocusedStage(_ model: RecordViewModel) -> some View {
        // ~76% of a 1080p screen — the cover plays as ambient art on a real
        // TV instead of looking like a thumbnail. The mirror adds size/6
        // beneath it, so the total stays comfortably inside 1080.
        reflectedCover(820)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Pieces

    private let coverSide: CGFloat = 520

    /// Edge-to-edge blurred copy of the cover, the ambient backdrop behind both
    /// stages. Fills the whole screen; `dark` scrim keeps foreground legible.
    private func blurredBackdrop(dark: Double) -> some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .blur(radius: 80, opaque: true)
        .overlay(Color.black.opacity(dark))
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: release.preferredCoverURL)
    }

    private func cover(_ size: CGFloat, cornerRadius: CGFloat = 0, shadowRadius: CGFloat = 0) -> some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(radius: shadowRadius)
        // Cross-fades when the cover URL changes (Discogs → resolved cover).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: release.preferredCoverURL)
    }

    /// Album cover on black with a faded mirror reflection beneath it — the
    /// look of older iTunes / Cover Flow visualizations. The cover is unframed
    /// (no rounding, no shadow); the reflection dissolves fully into the black.
    private func reflectedCover(_ size: CGFloat) -> some View {
        VStack(spacing: 0) {
            cover(size)
            cover(size)
                .scaleEffect(x: 1, y: -1)
                .frame(height: size / 6, alignment: .top)
                .clipped()
                // Mask the clipped strip so it fades from a faint reflection at
                // the top to fully transparent at the bottom — no hard cutoff.
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

    private var albumHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(release.title)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(release.artistDisplayName)
                .font(.system(size: 31))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(width: coverSide, alignment: .leading)
    }

    @ViewBuilder
    private func tracklist(_ model: RecordViewModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().controlSize(.large)
        case .failed:
            Text("Couldn't load the tracklist.")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.5))
        case .loaded:
            if let side = model.currentSide {
                VStack(alignment: .leading, spacing: 0) {
                    sideHeader(side)
                        .padding(.bottom, 12)
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)
                    ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(number: index + 1, title: track.title, composers: track.composers, duration: track.duration)
                    }
                }
            } else {
                Text("No tracklist available.")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func sideHeader(_ side: RecordSide) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(side.name)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if let total = Self.totalDuration(of: side) {
                Text(total)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
            }
        }
    }

    /// Sum of a side's track durations, or nil if any track lacks a parseable
    /// "m:ss" / "h:mm:ss" duration (so a partial total is never shown).
    private static func totalDuration(of side: RecordSide) -> String? {
        var total = 0
        for track in side.tracks {
            guard let secs = seconds(from: track.duration) else { return nil }
            total += secs
        }
        guard total > 0 else { return nil }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func seconds(from duration: String) -> Int? {
        let parts = duration.split(separator: ":")
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            nums.append(value)
        }
        switch nums.count {
        case 2: return nums[0] * 60 + nums[1]
        case 3: return nums[0] * 3600 + nums[1] * 60 + nums[2]
        default: return nil
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            Text(toast)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 28)
                .background(.black.opacity(0.55), in: Capsule())
                .transition(.opacity)
        }
    }

    // MARK: - Behavior

    private var subtitle: String {
        var parts: [String] = []
        if release.year > 0 { parts.append(String(release.year)) }
        parts.append(contentsOf: release.genres)
        parts.append(contentsOf: release.styles)
        return parts.joined(separator: " · ")
    }

    private func setMode(_ mode: RecordViewModel.DisplayMode, on model: RecordViewModel) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            switch mode {
            case .coverFocused: model.enterCoverFocused()
            case .informative: model.enterInformative()
            }
        }
    }

    /// Switches to the next/previous side. In cover-focused view the overlay is
    /// hidden, so a brief "Side B" toast confirms the change.
    private func changeSide(on model: RecordViewModel, forward: Bool) {
        let moved = forward ? model.flipToNextSide() : model.flipToPreviousSide()
        if moved, model.displayMode == .coverFocused, let side = model.currentSide {
            showToast(side.name)
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

/// Renders only the label — no focus ring, scale, or other chrome. The record
/// screen is one full-screen control, so any focus decoration just draws an
/// unwanted frame at the screen edge.
private struct AmbientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// One track row in the Apple Music–style side list: sequential number, title,
/// and right-aligned duration. No separators — matches Music on tvOS.
private struct TrackRow: View {
    let number: Int
    let title: String
    let composers: String
    let duration: String

    var body: some View {
        HStack(spacing: 24) {
            Text("\(number)")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 33))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !composers.isEmpty {
                    Text("by \(composers)")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 24)
            Text(duration)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
        }
        .padding(.vertical, 16)
    }
}
