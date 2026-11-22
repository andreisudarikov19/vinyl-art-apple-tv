import Nuke
import NukeUI
import SwiftData
import SwiftUI

/// Moves the cover to a place in the list (a sort or filter change, a
/// suggestion, the return from a record). `takesFocus` also puts focus on
/// the cover. Each request is new, so the same place can be asked for again.
struct CoverReveal: Equatable {
    let index: Int
    let takesFocus: Bool
    private let token = UUID()

    init(index: Int, takesFocus: Bool) {
        self.index = index
        self.takesFocus = takesFocus
    }
}

/// Classic Cover Flow browse mode: a 3D carousel of album covers with mirror
/// reflections over black, with the tide behind the centered cover (spec 06).
/// The whole view is one focusable control — left/right move through
/// covers, center-click opens the record. Only a window of covers around the
/// selection renders, so it scales to large collections.
struct CoverFlowView: View {
    let releases: [CachedRelease]
    var onOpen: (CachedRelease) -> Void
    /// Called on swipe-up. This view's onMoveCommand consumes the up gesture,
    /// so the parent uses this to move focus to the toolbar explicitly.
    var onMoveUp: () -> Void = {}
    /// A place to move the cover to; see `CoverReveal`.
    var reveal: CoverReveal?
    /// Reports the record under the needle, so the gallery can keep it there
    /// when the sort or filter changes.
    var onBrowse: (Int) -> Void = { _ in }
    /// The scale under the cover: one group per entry of `releases`.
    var tape = ScaleTape(groups: [])
    /// True while the tide moves. The gallery toolbar fades with it, so the
    /// gallery owns the flag and the toolbar reads it.
    @Binding var tideEngaged: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0
    @State private var didGrabInitialFocus = false
    @FocusState private var focused: Bool

    @Query private var preferences: [UserPreferences]
    @State private var tidePalette: HaloPalette = .placeholder
    /// Runs only while the tide moves, so it resumes where it stopped.
    @State private var tideClock = TideClock()
    /// The tide's fade: in over three seconds when it starts, out when a press stops it.
    @State private var tideOpacity: Double = 0
    @State private var haloIdleTask: Task<Void, Never>?

    /// The Gallery's switch, Ambient halo › Gallery. On by default.
    private var isAutoHalo: Bool {
        (preferences.first?.haloSettings ?? HaloSettings()).gallery == .on
    }

    // Tuning knobs
    // The vertical budget is spec 01 (design-handoff/specs/01-gallery-and-scale.md),
    // in points from the top of a 1080 pt screen. The cover is 552 pt square.
    private let coverSize: CGFloat = 552
    /// Cover (166 to 718) and its reflection (to 801): 15% of the cover's height.
    private var reflectionHeight: CGFloat { coverSize * 0.15 }
    private let coverTop: CGFloat = 166
    /// The album title starts 20 pt under the reflection.
    private let titleGap: CGFloat = 20
    /// The scale's box, 944 to 1016. The count is centred on it.
    private let scaleBoxTop: CGFloat = 944
    private let scaleBoxHeight: CGFloat = 72
    private let windowRadius = 6
    private let sideAngle: Double = 58
    private let sideScale: CGFloat = 0.84

    var body: some View {
        ZStack(alignment: .top) {
            background
            fades
            // The layout is placed from the top of the screen, not the safe
            // area, so the numbers in spec 01 apply directly.
            carousel
                .padding(.top, releases.isEmpty ? 0 : coverTop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if !releases.isEmpty {
                countLabel
                scale
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selectedIndex) { await refreshBackdrop() }
        .onChange(of: tideEngaged) { _, engaged in
            if engaged {
                tideClock.start(at: Date())
                withAnimation(.easeInOut(duration: TideTiming.galleryFadeIn)) { tideOpacity = 1 }
            } else {
                tideClock.stop(at: Date())
                withAnimation(.easeInOut(duration: TideTiming.galleryFadeOut)) { tideOpacity = 0 }
            }
        }
        .onChange(of: focused) { _, isFocused in
            // When focus leaves CoverFlow (e.g. up to the toolbar), the user
            // is no longer browsing here; cancel the idle timer so the halo
            // doesn't engage behind the scenes. When focus returns, re-arm.
            if isFocused {
                restartHaloIdleTimer()
            } else {
                cancelHaloIdleTimer()
            }
        }
        .onChange(of: reveal) { _, request in
            guard let request else { return }
            selectedIndex = min(max(request.index, 0), max(releases.count - 1, 0))
            // A pushed record hands focus back only after its pop settles, so
            // the cover takes focus a moment later, not at once.
            if request.takesFocus {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1000))
                    focused = true
                }
            }
        }
        .onChange(of: selectedIndex, initial: true) { _, index in
            guard releases.indices.contains(index) else { return }
            onBrowse(releases[index].releaseId)
        }
        .suppressesScreensaver(tideEngaged)
    }

    /// The focusable carousel: the cover row and the centred record's title
    /// block. Left and right move through covers, centre-click opens the
    /// record.
    private var carousel: some View {
        Button {
            if releases.indices.contains(selectedIndex) {
                onOpen(releases[selectedIndex])
            }
        } label: {
            Group {
                if releases.isEmpty {
                    Text("No matches")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    VStack(spacing: 0) {
                        flow
                            .frame(height: coverSize + reflectionHeight)
                        metadata
                            .padding(.top, titleGap)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: releases.isEmpty ? .infinity : nil)
        }
        .buttonStyle(PlainNoFocusStyle())
        .focusEffectDisabled()
        .focused($focused)
        // One control for the whole carousel, so it takes the centred
        // record's name, worded as the mosaic words its tiles.
        .accessibilityLabel(current?.galleryAccessibilityLabel ?? String(localized: "No matches"))
        .onMoveCommand { direction in
            switch direction {
            case .left:
                move(-1)
                restartHaloIdleTimer()
            case .right:
                move(1)
                restartHaloIdleTimer()
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
    }

    // MARK: - Pieces

    /// The tide behind the centre cover (design-handoff/specs/06-ambient-tide.md):
    /// the still low-tide glow, and the moving tide over it while the switch is
    /// on and the tide has started.
    private var background: some View {
        ZStack {
            Theme.ink
            TideGlow(shape: .gallery, main: tidePalette.main, reach: 0)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !tideEngaged)) { context in
                TideGlow(
                    shape: .gallery,
                    main: tidePalette.main,
                    reach: reduceMotion
                        ? Tide.reducedMotionReach
                        : Tide.reach(running: tideClock.running(at: context.date))
                )
            }
            .opacity(tideOpacity)
        }
        .ignoresSafeArea()
    }

    /// The ink fades (spec 01): the glow darkens to ink toward the left and
    /// right edges, ink sits behind the toolbar's top 160 pt, and behind the
    /// title and scale's bottom 270 pt, so yolk and white keep their contrast.
    private var fades: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Theme.ink.opacity(0.9), location: 0),
                    .init(color: Theme.ink.opacity(0), location: 0.22),
                    .init(color: Theme.ink.opacity(0), location: 0.78),
                    .init(color: Theme.ink.opacity(0.9), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Theme.ink.opacity(0.95), location: 0),
                        .init(color: Theme.ink.opacity(0.85), location: 0.5),
                        .init(color: Theme.ink.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: Theme.ink.opacity(0), location: 0),
                        .init(color: Theme.ink.opacity(0.95), location: 0.3),
                        .init(color: Theme.ink.opacity(0.95), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 270)
            }
        }
        .ignoresSafeArea()
    }

    /// The scale under the cover, 944 to 1016 pt. It goes to its idle look
    /// while the halo is on.
    private var scale: some View {
        Group {
            switch preferences.first?.scaleStyle ?? .slideRule {
            case .slideRule:
                SlideRuleScale(tape: tape, current: selectedIndex, total: releases.count, idle: tideEngaged)
            case .glassLens:
                GlassLensScale(tape: tape, current: selectedIndex, total: releases.count, idle: tideEngaged)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, scaleBoxTop)
    }

    /// "214 / 612", DM Mono 25 in quiet, right-aligned at the 80 pt margin and
    /// centred on the scale's box. Counts the browsed list, so a genre filter
    /// shows its own total. VoiceOver hears the count from the scale.
    private var countLabel: some View {
        HStack {
            Spacer(minLength: 0)
            Text("\(selectedIndex + 1) / \(releases.count)")
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
        }
        .padding(.trailing, Theme.safeSide)
        .frame(height: scaleBoxHeight)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, scaleBoxTop)
        .accessibilityHidden(true)
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
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: selectedIndex)
    }

    /// The album title leads (Fraunces 52/56, text colour) and the artist
    /// follows (Inter 29/36, body colour): title 821 to 877, artist 883 to 919.
    private var metadata: some View {
        VStack(spacing: 6) {
            Text(current?.title ?? "")
                .font(Theme.serif(Theme.Size.albumTitle))
                .tracking(-Theme.Size.albumTitle * 0.02)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(height: 56)
            Text(current?.artistDisplayName ?? "")
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.body)
                .lineLimit(1)
                .frame(height: 36)
        }
        .padding(.horizontal, Theme.safeSide)
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

    /// Refreshes the tide's colour when the focused cover changes. Also
    /// restarts the idle countdown: a focus change is "user input", so a
    /// running tide stops and starts again only after a minute without
    /// further navigation (switch on only).
    private func refreshBackdrop() async {
        guard let url = current?.preferredCoverURL,
              let image = try? await ImagePipeline.shared.image(for: url) else {
            restartHaloIdleTimer()
            return
        }
        tidePalette = HaloPalette.sleeve(from: image) ?? .placeholder
        restartHaloIdleTimer()
    }

    /// Cancels any in-flight idle countdown and starts a fresh wait.
    /// The tide stops immediately; it starts again after the idle time of no input.
    /// No-op when the Gallery's switch is off.
    private func restartHaloIdleTimer() {
        haloIdleTask?.cancel()
        tideEngaged = false
        guard isAutoHalo, focused else { return }
        haloIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TideTiming.galleryIdle))
            guard !Task.isCancelled else { return }
            tideEngaged = true
        }
    }

    private func cancelHaloIdleTimer() {
        haloIdleTask?.cancel()
        haloIdleTask = nil
        tideEngaged = false
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
                .frame(width: coverSize, height: coverSize * 0.15, alignment: .top)
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
        FittedSleeve(url: release.preferredCoverURL)
            .frame(width: coverSize, height: coverSize)
    }
}

/// Renders only the label — no focus ring or scale. The Cover Flow is one
/// full-screen control, so any default focus chrome just frames the screen.
private struct PlainNoFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
