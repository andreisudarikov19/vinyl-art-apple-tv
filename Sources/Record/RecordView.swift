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

struct RecordView: View {
    let release: CachedRelease

    @Environment(\.releaseDetailLoader) private var loader
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
            case .down: setMode(.coverFocused, on: model)
            case .up: setMode(.informative, on: model)
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
                cover(model, size: 620)
                infoPanel(model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(100)
        }
    }

    private func coverFocusedStage(_ model: RecordViewModel) -> some View {
        ZStack {
            AmbientGradientView(imageURL: release.preferredCoverURL)
            cover(model, size: 820)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func cover(_ model: RecordViewModel, size: CGFloat?) -> some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .aspectRatio(1, contentMode: size == nil ? .fill : .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size == nil ? 0 : 14))
        .shadow(radius: size == nil ? 0 : 40)
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
                VStack(alignment: .leading, spacing: 16) {
                    Text(side.name)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(side.tracks) { track in
                        HStack(spacing: 20) {
                            Text(track.position)
                                .frame(width: 70, alignment: .leading)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(track.title)
                                .foregroundStyle(.white)
                            Spacer(minLength: 20)
                            Text(track.duration)
                                .foregroundStyle(.white.opacity(0.5))
                                .monospacedDigit()
                        }
                        .font(.title3)
                    }
                }
            } else {
                Text("No tracklist available.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
            }
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
