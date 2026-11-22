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
    /// Set when the record was opened by Suggest: the sleeve then carries an
    /// "Another suggestion" sticker, and choosing it calls this.
    var onAnotherSuggestion: (() -> Void)?

    @Environment(\.releaseDetailLoader) private var loader
    @Environment(\.coverResolver) private var resolveCover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: RecordViewModel?
    @Environment(\.modelContext) private var modelContext
    /// The cover view's status line, "HALO ON" or "HALO OFF", and the task
    /// that takes it away after three seconds.
    @State private var haloStatus: String?
    @State private var haloStatusTask: Task<Void, Never>?

    @Query private var preferences: [UserPreferences]
    /// The sleeve's colours for the track list's tide.
    @State private var tidePalette: HaloPalette = .placeholder
    /// The cover view's halo has waited out its three seconds of dark and
    /// may show, if its switch says so.
    @State private var haloWaitIsOver = false
    @State private var idleTask: Task<Void, Never>?
    @FocusState private var screenFocused: Bool
    @FocusState private var discogsNoticeFocused: Bool
    @FocusState private var stickerFocused: Bool
    @State private var showingDiscogsQR = false
    /// How far a side longer than the screen has been scrolled, in points,
    /// with the heights that decide how far it can go. See `SideScroll`.
    @State private var listOffset: CGFloat = 0
    @State private var listContentHeight: CGFloat = 0
    @State private var listViewportHeight: CGFloat = 0
    /// Drives the cover-focused ken-burns: oscillates 1.0..1.03 with a 60s
    /// total cycle (30s each direction). Imperceptible per second; adds
    /// subtle life over a side of an LP. Disabled in Reduce Motion.
    @State private var coverBreath: CGFloat = 1.0
    /// The sleeve's slow drift in the cover view, across and up and down.
    @State private var coverDriftAcross: CGFloat = 0
    @State private var coverDriftUpDown: CGFloat = 0

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

    /// The three ambient-light switches (spec 03). Until Settings can change
    /// them they are what the old single switch gives: see `HaloSettings`.
    private var haloSettings: HaloSettings {
        preferences.first?.haloSettings ?? HaloSettings()
    }

    /// The track list's switch, Ambient halo › Track list. Off by default.
    private var isTrackListTideOn: Bool {
        haloSettings.trackList == .on
    }

    /// Whether the halo is drawn: only in the cover view, only when its
    /// switch (or the last Left or Right in Manual) says on, and only once
    /// the three seconds of dark are over.
    private var isHaloEngaged: Bool {
        guard viewModel?.displayMode == .coverFocused else { return false }
        return haloSettings.coverHaloIsOn && haloWaitIsOver
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
            focusStickerSoon()
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
            tidePalette = .placeholder
            return
        }
        if let image = try? await ImagePipeline.shared.image(for: url) {
            tidePalette = HaloPalette.sleeve(from: image) ?? .placeholder
        }
    }

    // MARK: - The cover view's halo (spec 05)

    /// Starts the halo's three seconds of dark, after which it fades in over
    /// three more. Called on opening the cover view and after Right in Manual.
    /// Does nothing more than stay dark when the halo is off.
    private func startHaloWait() {
        idleTask?.cancel()
        haloWaitIsOver = false
        guard haloSettings.coverHaloIsOn else { return }
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            haloWaitIsOver = true
        }
    }

    private func cancelHaloWait() {
        idleTask?.cancel()
        idleTask = nil
        haloWaitIsOver = false
    }

    /// Left and Right in the cover view. In Manual, Left turns the halo off
    /// and Right turns it on; the choice is kept, also between launches, and
    /// the status line answers every press, including one that changes
    /// nothing. With the switch On or Off the remote has no say.
    private func setManualHalo(_ on: Bool) {
        guard haloSettings.coverView == .manual else { return }
        if haloSettings.manualCoverHaloOn != on {
            UserPreferences.current(in: modelContext).haloSettings.manualCoverHaloOn = on
            if on {
                startHaloWait()
            } else {
                cancelHaloWait()
            }
        }
        showHaloStatus(on ? "HALO ON" : "HALO OFF")
    }

    /// Shows the status line at once and takes it away after three seconds.
    private func showHaloStatus(_ text: String) {
        haloStatusTask?.cancel()
        haloStatus = text
        haloStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { haloStatus = nil }
        }
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
        guard isTrackListTideOn else { return }
        backdropIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TideTiming.trackListIdle))
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
        // CoreHaptics hardware), so the flip is confirmed visually only, by
        // the dial and the track list.
        Button {
            // Select changes side on the record screen. In the cover view it
            // does nothing: that view is a display.
            if model.displayMode == .informative {
                changeSide(on: model, forward: true)
            }
        } label: {
            // top-leading alignment so a tall informative stage (lots of
            // tracks with multiple credits) anchors at the top instead of
            // being centred.
            ZStack(alignment: .topLeading) {
                if model.displayMode == .coverFocused {
                    coverFocusedStage(model).transition(.opacity)
                } else {
                    informativeStage(model).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The whole screen is the main focusable control. `.plain` + focusEffectDisabled
        // still leaves a focus ring framing the screen edge on tvOS, so use a
        // custom style that renders only the label.
        .buttonStyle(AmbientButtonStyle())
        .focusEffectDisabled()
        .focused($screenFocused)
        .accessibilityLabel("\(release.artistDisplayName), \(release.title)")
        .accessibilityHint("Swipe left or right to change sides. Swipe down and up to read a long side; down from its end reaches the Discogs line. Swipe up for the cover; there, left and right turn the halo off and on, and down returns.")
        .onMoveCommand { direction in
            if model.displayMode == .coverFocused {
                moveInCoverView(direction, on: model)
            } else {
                moveOnRecordScreen(direction, on: model)
            }
        }
        .task(id: model.displayMode) {
            // Mode transitions arm the relevant idle timer for the stage
            // we're entering, and cancel the one we're leaving.
            if model.displayMode == .coverFocused {
                startHaloWait()
            } else {
                cancelHaloWait()
                haloStatus = nil
            }
            if model.displayMode == .informative {
                restartBackdropIdleTimer()
            } else {
                cancelBackdropIdleTimer()
            }
        }
    }

    // MARK: - Stages

    /// The record screen (design-handoff/specs/04-record-screen.md): the sleeve,
    /// title and facts on the left, the side dial and its track list on the
    /// right. Placed from the edges of the screen, whatever the safe area is,
    /// so the spec's numbers apply directly.
    private func informativeStage(_ model: RecordViewModel) -> some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            // The left column is as tall as the screen allows and no taller,
            // so a long track list beside it cannot push the Discogs line down.
            let top = max(0, RecordLayout.dialTop - safe.top)
            let bottom = max(0, RecordLayout.bottom - safe.bottom)
            let sleeveDrop = RecordLayout.sleeveTop - RecordLayout.dialTop
            let leftHeight = max(0, geo.size.height - top - sleeveDrop - bottom)
            HStack(alignment: .top, spacing: RecordLayout.columnGap) {
                leftColumn(model)
                    .frame(width: RecordLayout.leftWidth, height: leftHeight, alignment: .topLeading)
                    .padding(.top, sleeveDrop)
                // Choosing the Discogs line swaps the track list for its
                // panel. The sleeve, title and table stay where they are.
                Group {
                    if showingDiscogsQR {
                        DiscogsReleasePanel(releaseId: release.releaseId)
                            .padding(.top, sleeveDrop)
                            .transition(.opacity)
                    } else {
                        tracklist(model)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.leading, max(0, RecordLayout.side - safe.leading))
            .padding(.trailing, max(0, RecordLayout.side - safe.trailing))
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(trackListBackdrop)
    }

    private func coverFocusedStage(_ model: RecordViewModel) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // The halo (spec 05): a steady rim round the sleeve, a faint aura
            // and soft patches drifting outward, in the sleeve's own colours.
            HaloLight(palette: tidePalette, isEngaged: isHaloEngaged, sleeveSide: 820)
                .ignoresSafeArea()
            featuredCover(820)
            // The only text this view ever shows: "HALO ON" or "HALO OFF",
            // 24 pt under the sleeve, for three seconds after Left or Right
            // in Manual.
            if let haloStatus {
                VStack {
                    Spacer()
                    Text(haloStatus)
                        .font(Theme.mono(Theme.Size.small, medium: true))
                        .tracking(Theme.Size.small * Theme.eyebrowTracking)
                        .foregroundStyle(Theme.body)
                        .padding(.bottom, 16)
                }
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The sleeve on the cover view, centred on the screen:
    /// - **A dark seat** under it, in place of the old shadow in the sleeve's
    ///   own colour (spec 05).
    /// - **Slow breathing** between 1.00x and 1.03x on a 60-second cycle
    ///   (30 s up, 30 s down).
    /// - **A slow wander** of a few points along a path that takes four
    ///   minutes to repeat, so no edge rests on the same pixels.
    /// Both are too slow to notice, and both stop under Reduce Motion.
    private func featuredCover(_ size: CGFloat) -> some View {
        cover(size)
            // The dark seat: a tight black shadow for a crisp edge and a wide
            // soft one that pushes the light back a little. In place of the
            // shadow in the sleeve's own colour, which vanished over the halo.
            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 4)
            .shadow(color: .black.opacity(0.55), radius: 46, x: 0, y: 14)
            .scaleEffect(coverBreath)
            .offset(x: coverDriftAcross)
            .offset(y: coverDriftUpDown)
            .onAppear { startCoverMotion() }
            .onDisappear { stopCoverMotion() }
    }

    /// Starts the breathing and the wander from rest, each with its own
    /// period (`CoverMotion`). Called every time the cover view opens: the
    /// motion ends when the view closes, so it has to be started afresh.
    private func startCoverMotion() {
        stopCoverMotion()
        guard !reduceMotion else { return }
        // A moment later, so the values above are in place before they move.
        Task { @MainActor in
            withAnimation(.easeInOut(duration: CoverMotion.breathPeriod / 2).repeatForever(autoreverses: true)) {
                coverBreath = CGFloat(CoverMotion.breath)
            }
            withAnimation(.easeInOut(duration: CoverMotion.periodAcross / 2).repeatForever(autoreverses: true)) {
                coverDriftAcross = CGFloat(CoverMotion.reach)
            }
            withAnimation(.easeInOut(duration: CoverMotion.periodUpDown / 2).repeatForever(autoreverses: true)) {
                coverDriftUpDown = CGFloat(CoverMotion.reach)
            }
        }
    }

    /// Puts the sleeve back at rest, without animating: its true size, at
    /// the far end of each drift, where the wander starts from. Under Reduce
    /// Motion it rests in the centre, as it will not move.
    private func stopCoverMotion() {
        let start = reduceMotion ? 0 : CGFloat(-CoverMotion.reach)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            coverBreath = 1
            coverDriftAcross = start
            coverDriftUpDown = start
        }
    }

    // MARK: - Pieces

    private let coverSide: CGFloat = 520

    /// The track list's tide (design-handoff/specs/06-ambient-tide.md): the still
    /// low-tide glow from the top left corner, and the moving tide over it once
    /// the switch is on and 15 s have passed without a press. It holds still on
    /// a press (the virtual time freezes) and fades in over four seconds.
    private var trackListBackdrop: some View {
        ZStack {
            Theme.ink
            TideGlow(shape: .trackList, main: tidePalette.main, reach: 0)
            if isTrackListTideOn {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isBackdropAmbientEngaged)) { context in
                    // Virtual time: the time the tide has been moving across all engagements.
                    let virtualT = backdropVirtualTime(at: context.date)
                    TideGlow(
                        shape: .trackList,
                        main: tidePalette.main,
                        reach: reduceMotion ? Tide.reducedMotionReach : Tide.reach(running: virtualT)
                    )
                    .opacity(min(1, virtualT / TideTiming.trackListFadeIn))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func cover(_ size: CGFloat, shadowRadius: CGFloat = 0) -> some View {
        FittedSleeve(url: release.preferredCoverURL)
            .frame(width: size, height: size)
            .shadow(radius: shadowRadius)
        // Cross-fades when the cover URL changes (Discogs → resolved cover).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: release.preferredCoverURL)
    }


    /// The left column: the sleeve, the album title (Fraunces, up to two
    /// lines), the artist, the facts table, and the Discogs line at its foot.
    private func leftColumn(_ model: RecordViewModel) -> some View {
        let longTitle = RecordFacts.titleTakesTwoLines(release.title)
        return VStack(alignment: .leading, spacing: 0) {
            cover(coverSide)
                .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 30)
                .overlay(alignment: .topLeading) {
                    if let onAnotherSuggestion {
                        suggestionSticker(onAnotherSuggestion)
                            .padding(20)
                    }
                }
            Text(release.title)
                .font(Theme.serif(Theme.Size.albumTitle))
                .tracking(-Theme.Size.albumTitle * 0.02)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
            Text(release.artistDisplayName)
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.body)
                .lineLimit(1)
                .padding(.top, 6)
            factsTable(model, compact: longTitle)
                .padding(.top, longTitle ? 20 : 28)
            Spacer(minLength: 12)
            discogsNotice
        }
    }

    /// Published, genre, style, label and length: a label column 186 pt wide
    /// in DM Mono, the values in Inter 25. Rows with nothing to say are left
    /// out. With a two-line title the rows sit a little closer, so the table
    /// clears the Discogs line.
    private func factsTable(_ model: RecordViewModel, compact: Bool) -> some View {
        let rows = RecordFacts.rows(
            year: release.year,
            albumYear: release.albumYear,
            country: model.country,
            genres: release.genres,
            styles: release.styles,
            label: release.labelName,
            durations: model.durations,
            titleTakesTwoLines: compact
        )
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(row.label)
                        .font(Theme.mono(Theme.Size.small, medium: true))
                        .tracking(Theme.Size.small * 0.12)
                        .foregroundStyle(Theme.quiet)
                        .frame(width: RecordLayout.factLabelWidth, alignment: .leading)
                    Text(factValue(row))
                        .font(Theme.sans(Theme.Size.small))
                        .lineLimit(row.lineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: compact ? 34 : 36, alignment: .center)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: rows)
    }

    /// A row's value in the text colour, with second-rank parts (the styles,
    /// the playing time) at 65%.
    private func factValue(_ row: RecordFactRow) -> AttributedString {
        var value = AttributedString(row.value)
        value.swiftUI.foregroundColor = Theme.text.opacity(row.isQuiet ? Theme.secondaryOpacity : 1)
        var tail = AttributedString(row.tail)
        tail.swiftUI.foregroundColor = Theme.text.opacity(Theme.secondaryOpacity)
        return value + tail
    }

    /// The Discogs attribution, at the foot of the left column. Discogs' API terms require it beside its data. Selecting it shows
    /// a QR code of the release page, as tvOS cannot open links.
    /// "Another suggestion", on the top left corner of a suggested record's
    /// sleeve like a shop sticker (spec 04). It says the record was suggested
    /// and offers the next one. Focus starts here; Down goes to the Discogs
    /// line and Right back to the sides.
    private func suggestionSticker(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SuggestionStickerLabel()
        }
        .buttonStyle(DiscogsNoticeButtonStyle())
        .focusEffectDisabled()
        .focused($stickerFocused)
        .accessibilityHint("Opens another record picked at random.")
        .onMoveCommand { direction in
            switch direction {
            case .down: discogsNoticeFocused = true
            case .right: screenFocused = true
            default: break
            }
        }
    }

    /// Moves focus from the sides to the left column: to the sticker, or to
    /// the Discogs line. Asked for a moment later, not inside the remote's
    /// own move, which tvOS is still settling and would otherwise win.
    private func focusLeftColumn(sticker: Bool) {
        Task { @MainActor in
            if sticker {
                stickerFocused = true
            } else {
                discogsNoticeFocused = true
            }
        }
    }

    /// Puts focus on the sticker when a suggested record opens. Asked twice,
    /// a moment apart: the first ask can come before the screen has settled.
    private func focusStickerSoon() {
        guard onAnotherSuggestion != nil else { return }
        Task { @MainActor in
            for delay in [150, 500] {
                try? await Task.sleep(for: .milliseconds(delay))
                if !stickerFocused { stickerFocused = true }
            }
        }
    }

    private var discogsNotice: some View {
        Button {
            setDiscogsPanel(!showingDiscogsQR)
        } label: {
            DiscogsNoticeLabel()
        }
        .buttonStyle(DiscogsNoticeButtonStyle())
        // Turns off tvOS's system focus block so only the label's own pill shows.
        .focusEffectDisabled()
        .focused($discogsNoticeFocused)
        .accessibilityHint("Shows a QR code for this release on discogs.com.")
        // Focus stays on the line while its panel is open, as nothing on the
        // panel takes focus. Menu closes the panel and leaves focus here;
        // with the panel closed, Menu goes back to the collection as usual.
        .onExitCommand(perform: showingDiscogsQR ? { setDiscogsPanel(false) } : nil)
        // Moving off the line closes the panel too, so the dial is never
        // steered while the track list is hidden.
        .onChange(of: discogsNoticeFocused) { _, focused in
            if !focused { setDiscogsPanel(false) }
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                // Up goes to the sticker when there is one, otherwise back
                // to the sides, where Down came from.
                if onAnotherSuggestion != nil {
                    stickerFocused = true
                } else {
                    screenFocused = true
                }
            case .right: screenFocused = true
            default: break
            }
        }
        // The label keeps room for its focus pill at the sides; pull it back
        // so the icon lines up with the table's left edge.
        .padding(.leading, -DiscogsNoticeLabel.sidePadding)
    }

    /// The right column: the side dial, then the chosen side's tracks and
    /// its total. The list is for reading; nothing in it takes focus.
    @ViewBuilder
    private func tracklist(_ model: RecordViewModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 300)
        case .failed:
            Text("Couldn't load the tracklist.")
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.quiet)
                .padding(.top, RecordLayout.sleeveTop - RecordLayout.dialTop)
        case .loaded:
            if let side = model.currentSide {
                VStack(alignment: .leading, spacing: 0) {
                    // A release without side letters has no selector: its one
                    // list starts level with the sleeve.
                    if side.isLettered {
                        SideDial(
                            sides: model.sides.map(\.id),
                            current: model.currentSideIndex,
                            focused: screenFocused
                        )
                        .padding(.bottom, RecordLayout.listTop - RecordLayout.dialTop - SideDial.height)
                    } else {
                        Color.clear
                            .frame(height: RecordLayout.sleeveTop - RecordLayout.dialTop)
                    }
                    // The list takes the rest of the column. A side taller
                    // than that is moved under it by Down and Up, and fades
                    // at the edge where there is more to read.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(number: index + 1, title: track.title, credits: track.credits, duration: track.duration, parts: track.parts)
                        }
                        sideTotal(side)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        listContentHeight = height
                    }
                    .offset(y: -listOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        listViewportHeight = height
                    }
                    .mask(listFade)
                }
                // Each side starts from its top.
                .onChange(of: model.currentSideIndex) { _, _ in
                    listOffset = 0
                }
            } else {
                Text("No tracklist available.")
                    .font(Theme.sans(Theme.Size.control))
                    .foregroundStyle(Theme.quiet)
                    .padding(.top, RecordLayout.sleeveTop - RecordLayout.dialTop)
            }
        }
    }

    /// The side's playing time, under the durations it sums, after a
    /// hairline. Left out when any track lacks a duration, so nothing is
    /// shown as 0:00. Sums the rows, so a suite's parts aren't counted again.
    @ViewBuilder
    private func sideTotal(_ side: RecordSide) -> some View {
        if let total = TrackDuration.total(of: side.tracks.map(\.duration)) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(side.isLettered ? side.name.uppercased() : "TOTAL")
                        .font(Theme.mono(Theme.Size.small, medium: true))
                        .tracking(Theme.Size.small * Theme.eyebrowTracking)
                        .foregroundStyle(Theme.quiet)
                    Spacer(minLength: 0)
                    Text(total)
                        .font(Theme.mono(Theme.Size.small, medium: true))
                        .foregroundStyle(Theme.text)
                }
                .padding(.top, 14)
            }
            .padding(.top, 12)
        }
    }

    /// Hides the list outside its part of the column, and fades its top or
    /// bottom edge while there is more to read that way.
    private var listFade: some View {
        let more = SideScroll.more(offset: listOffset, content: listContentHeight, viewport: listViewportHeight)
        return LinearGradient(
            stops: [
                .init(color: more.above ? .clear : .black, location: 0),
                .init(color: .black, location: more.above ? SideScroll.topFade : 0),
                .init(color: .black, location: more.below ? 1 - SideScroll.bottomFade : 1),
                .init(color: more.below ? .clear : .black, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Behavior

    /// Shows or hides the Discogs panel in place of the track list.
    private func setDiscogsPanel(_ shown: Bool) {
        guard shown != showingDiscogsQR else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            showingDiscogsQR = shown
        }
    }

    /// Moves a side that is longer than the screen. Does nothing to a side
    /// that fits, or at either end.
    private func scrollList(forward: Bool) {
        let next = SideScroll.next(
            from: listOffset,
            content: listContentHeight,
            viewport: listViewportHeight,
            forward: forward
        )
        guard next != listOffset else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            listOffset = next
        }
    }

    private func setMode(_ mode: RecordViewModel.DisplayMode, on model: RecordViewModel) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            switch mode {
            case .coverFocused: model.enterCoverFocused()
            case .informative: model.enterInformative()
            }
        }
    }

    /// Switches to the next or previous side of the record screen. The
    /// dial and the track list show the change.
    private func changeSide(on model: RecordViewModel, forward: Bool) {
        if forward {
            model.flipToNextSide()
        } else {
            model.flipToPreviousSide()
        }
    }

    /// The remote on the record screen: Left and Right change side, Down
    /// and Up read a long side, Up from the top opens the cover view.
    private func moveOnRecordScreen(_ direction: MoveCommandDirection, on model: RecordViewModel) {
        switch direction {
        case .up:
            if listOffset > 0 {
                // A long side that has been scrolled goes back up first;
                // Up opens the cover view only from the top of the list.
                scrollList(forward: false)
            } else {
                setMode(.coverFocused, on: model)
            }
        case .down:
            if SideScroll.more(offset: listOffset, content: listContentHeight, viewport: listViewportHeight).below {
                // On a side longer than the screen, Down reads on.
                scrollList(forward: true)
            } else {
                // At the end of the list, or on a side that fits, Down
                // goes to the Discogs line at the foot of the left column.
                focusLeftColumn(sticker: false)
            }
        case .right:
            changeSide(on: model, forward: true)
        case .left:
            if model.currentSideIndex == 0 {
                // Left from the first side goes to the left column: the
                // sticker on a suggested record, otherwise the Discogs line.
                focusLeftColumn(sticker: onAnotherSuggestion != nil)
            } else {
                changeSide(on: model, forward: false)
            }
        default:
            break
        }
        // Any press holds the track list's tide still for another 15 s.
        if model.displayMode == .informative {
            restartBackdropIdleTimer()
        }
    }

    /// The remote in the cover view (spec 05). Down returns to the track
    /// list. In Manual, Left turns the halo off and Right turns it on. Up
    /// does nothing, and no press interrupts the light: this view is a
    /// display, and a stray press should leave it alone.
    private func moveInCoverView(_ direction: MoveCommandDirection, on model: RecordViewModel) {
        switch direction {
        case .down: setMode(.informative, on: model)
        case .left: setManualHalo(false)
        case .right: setManualHalo(true)
        default: break
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

/// One track of the side list: its number, title and duration, with the
/// credits beneath the title. Nothing in the list takes focus.
///
/// The title may wrap to a second line. Each credit line (Composed by,
/// Vocals by, Lyrics by and so on) gets its own line beneath it, in the
/// order they appear on Discogs.
///
/// A suite or medley is one row, so one number, with its parts listed
/// beneath the credits, one line each with the part's duration. They are
/// quiet like the credits, so they read as the piece's movements rather
/// than as further tracks.
private struct TrackRow: View {
    let number: Int
    let title: String
    let credits: [TrackCredit]
    let duration: String
    let parts: [RecordTrack.Part]

    var body: some View {
        // First-text-baseline alignment so the number and duration sit on the
        // baseline of the title's first line when the title wraps.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(number)")
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.sans(Theme.Size.control, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(credits, id: \.role) { credit in
                    Text(credit.displayLine)
                        .font(Theme.sans(Theme.Size.small))
                        .foregroundStyle(Theme.quiet)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !parts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(part.title)
                                    .font(Theme.sans(Theme.Size.small))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !part.duration.isEmpty {
                                    Spacer(minLength: 24)
                                    Text(part.duration)
                                        .font(Theme.mono(Theme.Size.small))
                                }
                            }
                            .foregroundStyle(Theme.quiet)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 24)
            // Left empty when Discogs gives no duration; never 0:00.
            Text(duration)
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.body)
                .frame(minWidth: 120, alignment: .trailing)
                // A suite's part lines stretch the title column, which
                // would otherwise squeeze this to nothing.
                .fixedSize()
        }
        .padding(.vertical, 12)
    }
}

/// The sticker's label: a sparkle and "Another suggestion" in a pill 58 pt
/// high with a shadow under it. Yolk in focus, like every control in focus;
/// the surface colour with a line around it otherwise.
private struct SuggestionStickerLabel: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text("Another suggestion")
                .font(Theme.sans(Theme.Size.control, .semibold))
        }
        .foregroundStyle(isFocused ? Theme.onYolk : Theme.text)
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background {
            if isFocused {
                Capsule().fill(Theme.yolk)
            } else {
                Capsule()
                    .fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 14)
    }
}

/// The measures of the record screen, in points on a 1920 by 1080 screen
/// (design-handoff/specs/04-record-screen.md).
private enum RecordLayout {
    /// The left and right margins.
    static let side: CGFloat = 80
    /// The bottom margin: the safe line.
    static let bottom: CGFloat = 60
    /// The sleeve's top edge, and the dial's, which starts a little higher.
    static let sleeveTop: CGFloat = 80
    static let dialTop: CGFloat = 72
    /// The first track row's top edge.
    static let listTop: CGFloat = 186
    /// The left column holds the 520 pt sleeve and text up to 560 pt wide.
    /// The right column starts at 700 pt.
    static let leftWidth: CGFloat = 560
    static let columnGap: CGFloat = 60
    static let factLabelWidth: CGFloat = 186
}

/// The side selector: a small dial in the language of the scale under the
/// Gallery's cover. Fine ticks stand on a rule; each side has a taller tick
/// and its letter; the chosen side is a "Side F" pill with the yolk needle
/// under it, gliding to the new side when it changes. It takes no focus of
/// its own: the record screen is one control, and Left and Right change side.
private struct SideDial: View {
    /// The sides' letters, in order.
    let sides: [String]
    let current: Int
    /// The screen's main control has focus: the pill is yolk. When focus is
    /// elsewhere on the screen, the pill is outlined.
    let focused: Bool

    static let height: CGFloat = 88
    private let pillSize = CGSize(width: 160, height: 58)
    /// The rule sits 2 pt above the dial's bottom edge.
    private let ruleInset: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width / CGFloat(max(sides.count, 1))
            let ruleY = geo.size.height - ruleInset
            ZStack {
                Canvas { context, size in
                    // The rule, and fine ticks every 16 pt standing on it.
                    let rule = CGRect(x: 0, y: ruleY, width: size.width, height: 1)
                    context.fill(Path(rule), with: .color(Theme.lineStrong))
                    var x: CGFloat = 8
                    while x < size.width {
                        let tick = CGRect(x: x - 1, y: ruleY - 8, width: 2, height: 8)
                        context.fill(Path(tick), with: .color(.white.opacity(0.22)))
                        x += 16
                    }
                    // A taller white tick for each side.
                    for index in sides.indices {
                        let centre = (CGFloat(index) + 0.5) * step
                        let tick = CGRect(x: centre - 1, y: ruleY - 16, width: 2, height: 16)
                        context.fill(Path(tick), with: .color(.white))
                    }
                }
                // The letters. The chosen side's is hidden under its pill.
                ForEach(Array(sides.enumerated()), id: \.offset) { index, letter in
                    Text(letter)
                        .font(Theme.mono(Theme.Size.control, medium: true))
                        .foregroundStyle(index == current ? Color.clear : Theme.body)
                        .position(x: (CGFloat(index) + 0.5) * step, y: pillSize.height / 2)
                }
                if sides.indices.contains(current) {
                    pill(sides[current])
                        .position(x: (CGFloat(current) + 0.5) * step, y: pillSize.height / 2)
                    needle
                        .position(x: (CGFloat(current) + 0.5) * step, y: ruleY - 12)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: current)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    /// "Side F": yolk with dark text when the dial has focus, the surface
    /// colour with a line around it when focus is elsewhere.
    private func pill(_ letter: String) -> some View {
        Text("Side \(letter)")
            .font(Theme.sans(Theme.Size.control, focused ? .semibold : .medium))
            .foregroundStyle(focused ? Theme.onYolk : Theme.text)
            .frame(width: pillSize.width, height: pillSize.height)
            .background {
                if focused {
                    Capsule().fill(Theme.yolk)
                } else {
                    Capsule()
                        .fill(Theme.surface)
                        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
            }
    }

    /// The scale's needle: 4 by 24 pt, yolk, with its glow.
    private var needle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Theme.yolk)
            .frame(width: 4, height: 24)
            .shadow(color: Theme.yolk.opacity(0.85), radius: 7)
    }
}
