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
            let flipped = model.flipToNextSide()
            if flipped, model.displayMode == .coverFocused, let side = model.currentSide {
                showToast(side.name)
            }
        } label: {
            ZStack {
                if model.displayMode == .coverFocused {
                    coverFocusedStage(model).transition(.opacity)
                } else {
                    informativeStage(model).transition(.opacity)
                }
                toastOverlay
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(release.artistDisplayName), \(release.title). Click to flip the record.")
        .onMoveCommand { direction in
            switch direction {
            case .up: setMode(.coverFocused, on: model)
            case .down: setMode(.informative, on: model)
            default: break
            }
        }
    }

    // MARK: - Stages

    private func informativeStage(_ model: RecordViewModel) -> some View {
        ZStack {
            cover(model, size: nil)
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.6))
                .ignoresSafeArea()
            HStack(spacing: 80) {
                cover(model, size: 620, cornerRadius: 16, shadowRadius: 40)
                infoPanel(model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(100)
        }
    }

    private func coverFocusedStage(_ model: RecordViewModel) -> some View {
        ZStack {
            cover(model, size: nil)
                .blur(radius: 90)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
            cover(model, size: 880, shadowRadius: 30)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func cover(
        _ model: RecordViewModel,
        size: CGFloat?,
        cornerRadius: CGFloat = 0,
        shadowRadius: CGFloat = 0
    ) -> some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .aspectRatio(1, contentMode: size == nil ? .fill : .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(radius: shadowRadius)
        // Cross-fades when the cover URL changes (Discogs → resolved cover).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: release.preferredCoverURL)
    }

    private func infoPanel(_ model: RecordViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(release.artistDisplayName)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
            Text(release.title)
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
            Divider().overlay(.white.opacity(0.2))
            tracklist(model)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tracklist(_ model: RecordViewModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().controlSize(.large).padding(.top, 20)
        case .failed:
            Text("Couldn't load the tracklist.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
        case .loaded:
            if let side = model.currentSide {
                VStack(alignment: .leading, spacing: 0) {
                    sideHeader(side)
                    ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                        if index > 0 {
                            Divider()
                                .overlay(.white.opacity(0.12))
                                .padding(.leading, 56)
                        }
                        TrackRow(number: index + 1, title: track.title, duration: track.duration)
                    }
                }
            } else {
                Text("No tracklist available.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func sideHeader(_ side: RecordSide) -> some View {
        HStack {
            Text(side.name)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if let total = Self.totalDuration(of: side) {
                Text(total)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
        }
        .padding(.bottom, 10)
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

/// One track row in the Apple Music–style side list: sequential number,
/// title, and right-aligned duration.
private struct TrackRow: View {
    let number: Int
    let title: String
    let duration: String

    var body: some View {
        HStack(spacing: 20) {
            Text("\(number)")
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)
            Text(title)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 20)
            Text(duration)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
        }
        .font(.title3)
        .padding(.vertical, 14)
    }
}
