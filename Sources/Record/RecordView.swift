import Nuke
import NukeUI
import SwiftData
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

    @Query private var preferences: [UserPreferences]
    @State private var palette: CoverPalette = .placeholder
    @State private var autoHaloEngaged: Bool = false
    // Manual-mode pill state. Persists across records within an app session
    // (so toggling the halo on for one record keeps it on when you return);
    // resets to false on app launch via UserDefaults clearing in App.init.
    @AppStorage("haloPillEngaged") private var manualHaloEngaged: Bool = false
    @State private var idleTask: Task<Void, Never>?
    @FocusState private var screenFocused: Bool
    @FocusState private var pillFocused: Bool
    /// Drives the cover-focused ken-burns: oscillates 1.0..1.03 with a 60s
    /// total cycle (30s each direction). Imperceptible per second; adds
    /// subtle life over a side of an LP. Disabled in Reduce Motion.
    @State private var coverBreath: CGFloat = 1.0

    private var isAutoHalo: Bool {
        preferences.first?.haloAutoEngage ?? true
    }

    /// Whether the halo should currently be drawn. Only true while we're on
    /// the cover-focused stage — informative view has its own backdrop.
    private var isHaloEngaged: Bool {
        guard viewModel?.displayMode == .coverFocused else { return false }
        return isAutoHalo ? autoHaloEngaged : manualHaloEngaged
    }

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
        .task(id: release.preferredCoverURL) { await loadPalette() }
        .suppressesScreensaver(isHaloEngaged)
    }

    /// Pulls the (already-cached) cover from Nuke once it's available and
    /// extracts a 3-colour palette. Reruns when the URL changes (Discogs ->
    /// resolved Cover Art Archive art). Falls back to the placeholder palette
    /// so the halo doesn't render with a stale colour from a previous record.
    private func loadPalette() async {
        guard let url = release.preferredCoverURL else {
            palette = .placeholder
            return
        }
        if let image = try? await ImagePipeline.shared.image(for: url) {
            palette = CoverColor.palette(from: image, releaseId: release.releaseId)
        }
    }

    // MARK: - Halo idle timer (cover-focused, auto mode)

    /// Resets the cover-focused idle timer: halo off now, will re-engage after
    /// 3 seconds with no further input. Called on entering cover-focused and
    /// on every user input while there. Only used in auto mode.
    private func restartHaloIdleTimer() {
        idleTask?.cancel()
        autoHaloEngaged = false
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            autoHaloEngaged = true
        }
    }

    private func cancelHaloIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
        autoHaloEngaged = false
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
        // The whole screen is the main focusable control (the manual-mode
        // halo pill is a sibling focus target). `.plain` + focusEffectDisabled
        // still leaves a focus ring framing the screen edge on tvOS, so use a
        // custom style that renders only the label.
        .buttonStyle(AmbientButtonStyle())
        .focusEffectDisabled()
        .focused($screenFocused)
        .accessibilityLabel("\(release.artistDisplayName), \(release.title)")
        .accessibilityHint("Swipe left or right to change sides. Swipe up for the cover, down for the tracklist.")
        .onMoveCommand { direction in
            let wasCoverFocused = model.displayMode == .coverFocused
            switch direction {
            case .up:
                if wasCoverFocused, !isAutoHalo {
                    // Manual mode + already on cover stage: up reaches for the
                    // halo pill that lives below the cover (the focus engine
                    // wouldn't find it through "up" on its own).
                    pillFocused = true
                } else {
                    setMode(.coverFocused, on: model)
                }
            case .down: setMode(.informative, on: model)
            case .right: changeSide(on: model, forward: true)
            case .left: changeSide(on: model, forward: false)
            default: break
            }
            // Strict "any input -> halo off, 3s idle to re-engage" rule for
            // auto mode whenever we stay on the cover-focused stage.
            if isAutoHalo, model.displayMode == .coverFocused {
                restartHaloIdleTimer()
            }
        }
        .task(id: model.displayMode) {
            // Mode transitions: arm the idle timer when arriving at the
            // cover-focused stage (auto mode), cancel it on departure.
            if model.displayMode == .coverFocused, isAutoHalo {
                restartHaloIdleTimer()
            } else {
                cancelHaloIdleTimer()
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
        ZStack {
            Color.black.ignoresSafeArea()
            // Halo blobs sit behind the cover, born at the screen centre and
            // drifting outward. The cover hides their cores; only the bloom
            // past its silhouette becomes visible. The rich style adds a
            // breathing ambient base and a second tier of edge-origin blobs
            // after 60s of continuous engagement.
            HaloView(palette: palette, isEngaged: isHaloEngaged, style: .rich)
                .ignoresSafeArea()
            featuredCover(820)
            if !isAutoHalo {
                VStack {
                    Spacer()
                    haloPill
                        .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The cover displayed as ambient art on the cover-focused stage. Three
    /// touches separate this from the cover in the informative view:
    /// - **Cover-tinted drop shadow** anchors the cover in its halo. The
    ///   classic iTunes-Cover-Flow mirror reflection used to live here, but
    ///   it felt dated alongside the halo blobs and forced a layout dance
    ///   on engagement. A coloured shadow lets the cover read as the source
    ///   of the colour around it and removes the need for fade coordination.
    /// - **Slow ken-burns** breathes the cover between 1.00x and 1.03x on a
    ///   60-second cycle (30s up, 30s down). Imperceptible per second; adds
    ///   subtle life over a long viewing session. Disabled in Reduce Motion.
    /// - **Centred at screen centre**, no longer offset by reflection mass.
    private func featuredCover(_ size: CGFloat) -> some View {
        cover(size)
            .shadow(color: palette.dominant.opacity(0.4), radius: 60, x: 0, y: 20)
            .scaleEffect(coverBreath)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) {
                    coverBreath = 1.03
                }
            }
    }

    /// Manual-mode toggle pill: liquid glass capsule below the cover.
    /// Only rendered when haloAutoEngage is OFF.
    private var haloPill: some View {
        Button {
            manualHaloEngaged.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle.dotted")
                Text("Halo")
            }
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(manualHaloEngaged ? .black : .white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background {
                if manualHaloEngaged {
                    Capsule().fill(.white.opacity(0.92))
                } else {
                    haloPillGlass
                }
            }
        }
        .buttonStyle(.plain)
        .focused($pillFocused)
        .accessibilityLabel(manualHaloEngaged ? "Halo on" : "Halo off")
        .accessibilityHint("Toggles the ambient halo around the cover.")
        // Down from the pill returns focus to the cover-screen button. Other
        // directions are no-ops (pill is the only horizontal control here).
        .onMoveCommand { direction in
            if direction == .down { screenFocused = true }
        }
    }

    @ViewBuilder
    private var haloPillGlass: some View {
        if #available(tvOS 26.0, *) {
            Capsule().fill(.regularMaterial).glassEffect()
        } else {
            Capsule().fill(.regularMaterial)
        }
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
                    HStack(alignment: .center, spacing: 24) {
                        sideTuner(model)
                            .frame(maxWidth: .infinity)
                        if let total = Self.totalDuration(of: side) {
                            Text(total)
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.4))
                                .monospacedDigit()
                        }
                    }
                    .padding(.bottom, 18)
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

    /// A vintage-radio-tuner-styled side selector: a thin hairline running
    /// the width of the tracklist, with each side's letter label spaced
    /// evenly above it, and a Liquid Glass pill "needle" that glides to the
    /// current side. The letter inside the thumb stands in for the current
    /// side's static label (which we hide so the thumb doesn't double-print).
    /// Falls back to a single-position display for unsided tracklists (CD
    /// rips and the like).
    private func sideTuner(_ model: RecordViewModel) -> some View {
        let sides = model.sides
        let currentIndex = model.currentSideIndex
        let count = max(sides.count, 1)

        return GeometryReader { geo in
            let width = geo.size.width
            let segmentWidth = width / CGFloat(count)
            let centerY = geo.size.height / 2

            ZStack {
                // Hairline along the bottom — replaces the old standalone
                // divider that used to sit beneath the side header.
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(height: 1)
                }

                // Tick marks dropping into the hairline at each side's
                // position. Subtle — they orient the eye to the available
                // sides without competing with the labels.
                ForEach(0..<sides.count, id: \.self) { i in
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: 8)
                        .position(
                            x: CGFloat(i) * segmentWidth + segmentWidth / 2,
                            y: geo.size.height - 4
                        )
                }

                // Static side letters. The current side's letter is rendered
                // transparent so the moving thumb's letter doesn't overlap
                // a stationary one.
                ForEach(Array(sides.enumerated()), id: \.element.id) { i, side in
                    Text(side.id)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(i == currentIndex ? Color.clear : Color.white.opacity(0.35))
                        .monospacedDigit()
                        .position(
                            x: CGFloat(i) * segmentWidth + segmentWidth / 2,
                            y: centerY
                        )
                }

                // The needle — a Liquid Glass capsule carrying the current
                // side's letter, sliding between positions on a spring.
                if sides.indices.contains(currentIndex) {
                    tunerThumb(letter: sides[currentIndex].id)
                        .position(
                            x: CGFloat(currentIndex) * segmentWidth + segmentWidth / 2,
                            y: centerY
                        )
                        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: currentIndex)
                }
            }
        }
        .frame(height: 60)
    }

    @ViewBuilder
    private func tunerThumb(letter: String) -> some View {
        ZStack {
            tunerThumbGlass
            Text(letter)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 52, height: 40)
    }

    @ViewBuilder
    private var tunerThumbGlass: some View {
        if #available(tvOS 26.0, *) {
            Capsule().fill(.regularMaterial).glassEffect()
        } else {
            Capsule().fill(.ultraThinMaterial)
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
///
/// Title is allowed to wrap to a second line for long song names rather than
/// truncating with an ellipsis — the side list has vertical room. Composers
/// drop to their own line beneath the title (not beside it on the same row
/// where a long title would have pushed them off-screen anyway).
private struct TrackRow: View {
    let number: Int
    let title: String
    let composers: String
    let duration: String

    var body: some View {
        // First-text-baseline alignment so the number and duration sit on the
        // baseline of the title's *first* line when the title wraps —
        // otherwise center alignment would float them awkwardly between two
        // title lines.
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text("\(number)")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 33))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !composers.isEmpty {
                    Text("by \(composers)")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 24)
            Text(duration)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
        }
        .padding(.vertical, 16)
    }
}
