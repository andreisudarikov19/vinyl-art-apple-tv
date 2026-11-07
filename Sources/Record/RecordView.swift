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

    /// Informative-view backdrop ambient motion: engages after 15 s of
    /// stillness and freezes mid-motion the instant the user interacts.
    /// `backdropEngagedAt` is the wall-clock moment the current engagement
    /// started (nil while paused). `backdropFrozenTime` is the total accrued
    /// "virtual time" the motion has run across previous engagements — when
    /// the ambient re-engages it resumes from this point, so the cycles pick
    /// up at exactly the phase they were paused at. The 4 s fade-in is also
    /// driven off virtual time (min(1, virtualT / 4)) so it pauses with the
    /// rest of the motion instead of continuing to ramp during freeze.
    @State private var backdropEngagedAt: Date?
    @State private var backdropFrozenTime: TimeInterval = 0
    @State private var backdropIdleTask: Task<Void, Never>?

    private var isAutoHalo: Bool {
        preferences.first?.haloAutoEngage ?? true
    }

    /// Whether the halo should currently be drawn. Only true while we're on
    /// the cover-focused stage — informative view has its own backdrop.
    private var isHaloEngaged: Bool {
        guard viewModel?.displayMode == .coverFocused else { return false }
        return isAutoHalo ? autoHaloEngaged : manualHaloEngaged
    }

    /// True whenever the informative-view backdrop ambient drift is running
    /// (post-15s idle, paused on input). Used alongside the halo to gate
    /// screensaver suppression — both ambient states keep the screen safe.
    private var isBackdropAmbientEngaged: Bool {
        backdropEngagedAt != nil
    }

    /// Either ambient state (cover-focused halo or informative backdrop
    /// drift) is active — keep tvOS's screensaver held back so it doesn't
    /// interrupt the moving pixels that are themselves the burn-in defence.
    private var suppressesSystemScreensaver: Bool {
        isHaloEngaged || isBackdropAmbientEngaged
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
        .suppressesScreensaver(suppressesSystemScreensaver)
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

    // MARK: - Backdrop ambient idle timer (informative view)

    /// Freezes the ambient motion at its current configuration and arms a
    /// 15-second timer that will resume the motion from that frozen state.
    /// Called on entering informative view and on every directional input
    /// while there. The freeze is achieved by capturing the elapsed virtual
    /// time into `backdropFrozenTime` and nilling `backdropEngagedAt` — no
    /// fade-out animation, the motion just holds where it is.
    private func restartBackdropIdleTimer() {
        backdropIdleTask?.cancel()
        freezeBackdropMotion()
        backdropIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            // Resume: set the new engagement origin to now. Virtual time
            // continues from backdropFrozenTime onward.
            backdropEngagedAt = Date()
        }
    }

    private func cancelBackdropIdleTimer() {
        backdropIdleTask?.cancel()
        backdropIdleTask = nil
        freezeBackdropMotion()
    }

    /// Captures however much virtual time elapsed since the most recent
    /// engagement into `backdropFrozenTime`, then clears `backdropEngagedAt`
    /// so virtual time stops advancing. Idempotent — calling on an already
    /// frozen motion is a no-op.
    private func freezeBackdropMotion() {
        guard let engagedAt = backdropEngagedAt else { return }
        backdropFrozenTime += Date().timeIntervalSince(engagedAt)
        backdropEngagedAt = nil
    }

    /// Total accrued virtual time the backdrop motion has been engaged
    /// for, as of `now`. While engaged this advances at wall-clock pace;
    /// while paused (`backdropEngagedAt == nil`) it's frozen at the last
    /// captured value.
    private func backdropVirtualTime(at now: Date) -> TimeInterval {
        if let engagedAt = backdropEngagedAt {
            return backdropFrozenTime + now.timeIntervalSince(engagedAt)
        }
        return backdropFrozenTime
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
            // top-leading alignment so a tall informative stage (lots of
            // tracks with multiple credits) anchors at the top instead of
            // being centred — the latter would push the cover above the
            // visible area as the tracklist grew. The toast overrides with
            // its own centred frame so it still appears mid-screen.
            ZStack(alignment: .topLeading) {
                if model.displayMode == .coverFocused {
                    coverFocusedStage(model).transition(.opacity)
                } else {
                    informativeStage(model).transition(.opacity)
                }
                toastOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
            // Same rule for the informative backdrop, with a 15 s idle
            // window: any directional input restarts the wait.
            if model.displayMode == .informative {
                restartBackdropIdleTimer()
            }
        }
        .task(id: model.displayMode) {
            // Mode transitions arm the relevant idle timer for the stage
            // we're entering, and cancel the one we're leaving.
            if model.displayMode == .coverFocused, isAutoHalo {
                restartHaloIdleTimer()
            } else {
                cancelHaloIdleTimer()
            }
            if model.displayMode == .informative {
                restartBackdropIdleTimer()
            } else {
                cancelBackdropIdleTimer()
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

    /// Edge-to-edge blurred copy of the cover, the ambient backdrop behind
    /// the informative stage. Fills the whole screen; `dark` scrim keeps
    /// foreground legible.
    ///
    /// The backdrop drifts: a slow ken-burns zoom (60 s cycle), a wandering
    /// pan (75 s side to side, ~107 s up and down) and a gentle saturation
    /// breath (40 s). The cycles are out of phase so the combined motion
    /// doesn't visibly repeat for several minutes — rewards the user for
    /// lingering on the tracklist with a quiet "the cover is alive" reading
    /// without ever competing for attention with the title / artist / tracks.
    /// Reduce Motion freezes all three.
    private func blurredBackdrop(dark: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            // Virtual time: accrued time the motion has been engaged across
            // ALL engagements so far. Frozen when paused, resumes from the
            // exact same value on the next engagement — every cycle (zoom,
            // pan, saturation, fade) picks up at the phase it was paused at.
            let virtualT = backdropVirtualTime(at: context.date)
            // Fade-in: 4-second ease driven off virtual time, so it pauses
            // along with the motion when the user interacts.
            let fade = min(1.0, virtualT / 4.0)
            // Three out-of-phase cycles. The scale formula has a non-zero
            // baseline (+0.20 * fade) independent of zoom phase: that
            // guarantees the image is at least ~20% over-scaled whenever
            // any pan is happening, keeping the image's edges past the
            // screen's edges in every direction so the black "back" can
            // never appear. Pan ±80pt on a 1080pt-tall frame requires
            // scale ≥ 1.0 + 80/540 ≈ 1.148; the 1.20 baseline gives a
            // ~5% safety margin against any wobble.
            let zoomPhase = (sin(virtualT * 2 * .pi / 60.0) + 1) / 2 // 0..1 over 60s
            let scale: CGFloat = reduceMotion
                ? 1.0
                : 1.0 + (0.20 + 0.25 * CGFloat(zoomPhase)) * CGFloat(fade)
            let panX: CGFloat = reduceMotion
                ? 0
                : CGFloat(sin(virtualT * 2 * .pi / 75.0) * 80 * fade)
            // A cosine at 0.7× the horizontal frequency: the two axes never
            // line up, so the pan wanders in a Lissajous-style path rather
            // than tracing an ellipse or just wobbling left-right.
            let panY: CGFloat = reduceMotion
                ? 0
                : CGFloat(cos(virtualT * 2 * .pi / 75.0 * 0.7) * 80 * fade)
            // Saturation modulated as a delta off 1.0 so a fade=0 produces
            // a neutral saturation rather than a wrong base value.
            let saturationDelta = sin(virtualT * 2 * .pi / 40.0) * 0.12
            let saturation: Double = reduceMotion
                ? 1.0
                : 1.0 + saturationDelta * fade

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
            // Transforms applied AFTER the blur so the blur isn't recomputed
            // every frame — only the cheap zoom / pan / saturation filters
            // re-evaluate on each timeline tick.
            .scaleEffect(scale)
            .offset(x: panX, y: panY)
            .saturation(saturation)
            .overlay(Color.black.opacity(dark))
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: release.preferredCoverURL)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(release.title)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(release.artistDisplayName)
                .font(.system(size: 31))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            // Year, genres, and styles are categorical metadata — render as
            // frosted-glass tag pills that flow within the cover's width and
            // wrap to additional rows when they don't fit on one line. The
            // year pill carries a calendar SF Symbol so it reads as a date
            // anchor at a glance; genre / style pills are text-only.
            if !catalogTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(catalogTags, id: \.self) { tag in
                        tagPill(tag)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(width: coverSide, alignment: .leading)
    }

    /// The line of "1985 · Jazz · Big Band" categorical metadata, split into
    /// individual tags. Year goes first (chronological anchor and the only
    /// pill that carries an icon), then genres, then more-specific styles.
    private var catalogTags: [CatalogTag] {
        var out: [CatalogTag] = []
        if release.year > 0 {
            out.append(CatalogTag(label: String(release.year), systemImage: "calendar"))
        }
        out.append(contentsOf: release.genres.map { CatalogTag(label: $0, systemImage: nil) })
        out.append(contentsOf: release.styles.map { CatalogTag(label: $0, systemImage: nil) })
        return out
    }

    private func tagPill(_ tag: CatalogTag) -> some View {
        HStack(spacing: 8) {
            if let symbol = tag.systemImage {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
            }
            Text(tag.label)
                .font(.system(size: 22, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(tagPillBackground)
    }

    /// Frosted glass for the catalog tag pills: an ultra-thin material for
    /// the blurred translucency behind the text, plus a thin white stroke
    /// for the edge highlight that sells the "glass" reading at TV viewing
    /// distance. No tvOS 26 dependency — `.ultraThinMaterial` is available
    /// on every supported version.
    private var tagPillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            )
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
                    // Hairline lives in the parent ZStack now so it runs the
                    // full row width — under the slider AND the duration —
                    // instead of being clipped to the slider's column.
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(.white.opacity(0.18))
                            .frame(height: 1)
                        HStack(alignment: .center, spacing: 24) {
                            sideTuner(model)
                                .frame(maxWidth: .infinity)
                            // Sums the rows, so a suite's parts aren't counted again.
                            if let total = TrackDuration.total(of: side.tracks.map(\.duration)) {
                                Text(total)
                                    .font(.system(size: 24))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.bottom, 18)
                    ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(number: index + 1, title: track.title, credits: track.credits, duration: track.duration, parts: track.parts)
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
                // Tick marks at each side's position, dropping into the
                // hairline (which lives in the parent ZStack now so it can
                // stretch under the duration text too).
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
                // transparent so the moving thumb's "Side X" label doesn't
                // double-print on a stationary letter behind it.
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
                // side's full name ("Side A"), sliding between positions on
                // a spring. The "Side" word lives here so it's prominent
                // without needing a separate header.
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
            Text("Side \(letter)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 120, height: 44)
    }

    @ViewBuilder
    private var tunerThumbGlass: some View {
        if #available(tvOS 26.0, *) {
            Capsule().fill(.regularMaterial).glassEffect()
        } else {
            Capsule().fill(.ultraThinMaterial)
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
/// truncating with an ellipsis — the side list has vertical room. Credit
/// lines (Composed by / Vocals by / Backing vocals by / Lyrics by / etc.)
/// each get their own line beneath the title in the same subdued style,
/// in the order they appear on Discogs.
///
/// A suite or medley is one row, so one number, with its parts listed
/// beneath the credits, one line each with the part's duration. They're
/// subdued like the credits, so they read as the piece's movements rather
/// than as further tracks.
private struct TrackRow: View {
    let number: Int
    let title: String
    let credits: [TrackCredit]
    let duration: String
    let parts: [RecordTrack.Part]

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
                ForEach(credits, id: \.role) { credit in
                    Text(credit.displayLine)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !parts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(part.title)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !part.duration.isEmpty {
                                    Spacer(minLength: 24)
                                    Text(part.duration)
                                        .monospacedDigit()
                                }
                            }
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 24)
            Text(duration)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                // A suite's part lines stretch the title column, which
                // would otherwise squeeze this to nothing.
                .fixedSize()
        }
        .padding(.vertical, 16)
    }
}

/// One pill in the catalog-tag row beneath the album header. The optional
/// `systemImage` lets the year tag display a calendar glyph in front of its
/// label while genres / styles stay text-only.
private struct CatalogTag: Hashable {
    let label: String
    let systemImage: String?
}

/// Simple flow layout: places subviews left-to-right, wraps to the next line
/// when the next subview wouldn't fit in the proposed width. Used for the
/// catalog tag strip under the album header so genres / styles wrap cleanly
/// inside the cover's width instead of overflowing or truncating.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arranged = arrange(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: arranged.width, height: arranged.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(subviews: subviews, maxWidth: bounds.width)
        for placement in arranged.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y),
                proposal: .unspecified
            )
        }
    }

    private struct Placement {
        let subview: LayoutSubview
        let x: CGFloat
        let y: CGFloat
    }

    private struct Arrangement {
        let width: CGFloat
        let height: CGFloat
        let placements: [Placement]
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        var placements: [Placement] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Wrap if this subview wouldn't fit on the current line (but
            // never wrap at the very start of a line — a single subview
            // wider than the line just overflows rather than disappearing).
            if cursorX > 0, cursorX + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, cursorX - spacing)
                cursorX = 0
                cursorY += lineHeight + spacing
                lineHeight = 0
            }
            placements.append(Placement(subview: subview, x: cursorX, y: cursorY))
            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, cursorX - spacing)
        return Arrangement(
            width: max(0, maxRowWidth),
            height: cursorY + lineHeight,
            placements: placements
        )
    }
}
