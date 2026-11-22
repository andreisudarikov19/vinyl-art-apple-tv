import Nuke
import NukeUI
import SwiftData
import SwiftUI

/// The Grid (design-handoff/specs/09-grid.md): a wall of sleeves that takes
/// the whole screen, seven across and four whole rows high, with the sleeve
/// in focus redrawn on a yolk card above it.
///
/// The whole wall is one focusable control, as the Gallery's cover flow is.
/// It keeps its own place in the collection (`index`) and moves the wall
/// under the focus, so the row in focus is the second of the four wherever
/// the ends of the wall allow. The toolbar is the Gallery's: it is on screen
/// only while it has focus, which the parent decides.
struct MosaicGridView: View {
    let releases: [CachedRelease]
    var onOpen: (CachedRelease) -> Void
    /// Up from the first row: the parent moves focus to the toolbar.
    var onMoveUp: () -> Void = {}
    /// The record to land on: the one the collection was last on.
    var landingID: Int?
    /// A new value lands the wall on `landingID` again (the return from a
    /// record); `takesFocus` also puts focus on the wall.
    var reveal: CoverReveal?
    /// Told the record in focus whenever it changes.
    var onBrowse: (Int) -> Void = { _ in }
    /// The scale's tape: one entry per record, in the wall's order.
    var tape = ScaleTape(groups: [])
    /// The filter in force, for the chip: a genre and, with it, a style.
    var filterGenre: String?
    var filterStyle: String?
    /// The toolbar is on screen: the dark fade is drawn under it and the
    /// filter chip is hidden.
    var toolbarShown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var preferences: [UserPreferences]
    @FocusState private var focused: Bool

    /// The record in focus, as a place in `releases`.
    @State private var index = 0
    /// The row of the collection at the top of the screen.
    @State private var topRow = 0
    @State private var glowColor = Color(white: 0.15)
    @State private var palette = HaloPalette.placeholder
    /// The scale is on screen: only while moving.
    @State private var scaleShown = false
    @State private var scaleTask: Task<Void, Never>?
    /// Idle: the wall is dim, the card dark, the halo up.
    @State private var idle = false
    @State private var idleTask: Task<Void, Never>?
    @State private var didLand = false

    private var haloIsOn: Bool {
        (preferences.first?.haloSettings ?? HaloSettings()).gallery == .on
    }

    private var current: CachedRelease? {
        releases.indices.contains(index) ? releases[index] : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let grid = GridMeasures(size: proxy.size, count: releases.count)
            Button {
                select()
            } label: {
                ZStack(alignment: .topLeading) {
                    CollectionGlowBackground(glowColor: glowColor)
                    wall(grid)
                    GridMatrix(grid: grid, topRow: topRow)
                    // Idle: the wall drops to about a quarter of its brightness.
                    Theme.ink
                        .opacity(idle ? GridLook.idleDim : 0)
                        .animation(.easeInOut(duration: idle ? GridLook.idleIn : GridLook.idleOut), value: idle)
                    halo(grid)
                    card(grid)
                    scaleLayer(grid)
                    toolbarFade
                    chip
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .buttonStyle(GridBareButtonStyle())
            .focusEffectDisabled()
            .focused($focused)
            .accessibilityLabel(current?.galleryAccessibilityLabel ?? "")
            .onMoveCommand { direction in
                move(direction)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !didLand else { return }
            didLand = true
            land(animated: false)
        }
        .onChange(of: reveal) { _, request in
            land(animated: false)
            if request?.takesFocus == true {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    focused = true
                }
            }
        }
        .onChange(of: releases.map(\.releaseId)) { _, _ in
            // A sort or filter change: stay on the record if it is still there.
            land(animated: false)
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                restartIdleTimer()
            } else {
                // Focus is on the toolbar: nothing here is being browsed.
                cancelIdleTimer()
                hideScale()
            }
        }
        .task(id: current?.releaseId) { await refreshColours() }
        .suppressesScreensaver(idle)
    }

    // MARK: - The wall

    /// The sleeves, square and edge to edge. Only the rows on screen and two
    /// beyond each edge are drawn; the wall moves under them.
    private func wall(_ grid: GridMeasures) -> some View {
        let rows = grid.drawnRows(topRow: topRow)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(rows, id: \.self) { row in
                ForEach(0..<GridMeasures.columns, id: \.self) { column in
                    let place = row * GridMeasures.columns + column
                    if place < releases.count {
                        GridTile(release: releases[place], side: grid.side)
                            .position(
                                x: CGFloat(column) * grid.pitch + grid.side / 2,
                                y: CGFloat(row) * grid.pitch + grid.side / 2
                            )
                    }
                }
            }
        }
        .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
        .offset(y: grid.wallOffset(topRow: topRow))
        .animation(reduceMotion ? nil : .easeInOut(duration: GridLook.rowGlide), value: topRow)
    }

    // MARK: - The sleeve in focus

    /// The yolk card: the sleeve at 1.18 times its size with its title and
    /// artist beneath. It is centred on its cell and moved inward where it
    /// would leave the safe area. Idle turns it dark.
    @ViewBuilder
    private func card(_ grid: GridMeasures) -> some View {
        if let release = current {
            let frame = grid.cardFrame(index: index, topRow: topRow)
            GridCard(release: release, idle: idle)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: index)
                .animation(reduceMotion ? nil : .easeInOut(duration: GridLook.rowGlide), value: topRow)
        }
    }

    /// Idle: the cover view's halo behind the card, at the card's sleeve
    /// size and centred on it. It is drawn on black, so it is screened over
    /// the dimmed wall.
    @ViewBuilder
    private func halo(_ grid: GridMeasures) -> some View {
        let frame = grid.cardFrame(index: index, topRow: topRow)
        let sleeveCentre = CGPoint(x: frame.midX, y: frame.minY + GridLook.cardMargin + GridLook.cardSleeve / 2)
        HaloLight(palette: palette, isEngaged: idle && haloIsOn, sleeveSide: Double(GridLook.cardSleeve))
            .frame(width: grid.size.width, height: grid.size.height)
            .offset(x: sleeveCentre.x - grid.size.width / 2, y: sleeveCentre.y - grid.size.height / 2)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    // MARK: - The scale

    /// The Gallery's scale at the foot of the screen, over a dark fade, only
    /// while focus is moving.
    private func scaleLayer(_ grid: GridMeasures) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: Theme.ink.opacity(0), location: 0),
                    .init(color: Theme.ink.opacity(0.94), location: 0.62),
                    .init(color: Theme.ink.opacity(0.97), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: grid.size.width, height: grid.size.height - GridLook.scaleFadeTop)
            .offset(y: GridLook.scaleFadeTop)
            scale
                .frame(width: SlideRuleScale.size.width, height: SlideRuleScale.size.height)
                .position(x: grid.size.width / 2, y: GridLook.scaleTop + SlideRuleScale.size.height / 2)
            Text(verbatim: "\(index + 1) / \(releases.count)")
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .frame(width: 240, alignment: .trailing)
                .position(x: grid.size.width - Theme.safeSide - 120, y: GridLook.scaleTop + 50)
        }
        .frame(width: grid.size.width, height: grid.size.height, alignment: .topLeading)
        .opacity(scaleShown ? 1 : 0)
        .animation(.easeInOut(duration: GridLook.scaleFade), value: scaleShown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var scale: some View {
        switch preferences.first?.scaleStyle ?? .slideRule {
        case .slideRule:
            SlideRuleScale(tape: tape, current: index, total: releases.count, idle: false)
        case .glassLens:
            GlassLensScale(tape: tape, current: index, total: releases.count, idle: false)
        }
    }

    // MARK: - Over the wall

    /// The dark fade the toolbar comes in over.
    private var toolbarFade: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.ink.opacity(0.96), location: 0),
                .init(color: Theme.ink.opacity(0.9), location: 0.48),
                .init(color: Theme.ink.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: GridLook.toolbarFadeHeight)
        .frame(maxWidth: .infinity)
        .opacity(toolbarShown ? 1 : 0)
        .animation(.easeInOut(duration: GridLook.toolbarFade), value: toolbarShown)
        .allowsHitTesting(false)
    }

    /// The mark a filter leaves in the top right while the toolbar is away.
    /// Not a control: it takes no focus.
    @ViewBuilder
    private var chip: some View {
        if let genre = filterGenre {
            HStack(spacing: Theme.controlGap) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 26))
                HStack(spacing: 0) {
                    Text(verbatim: filterStyle == nil ? genre : "\(genre): ")
                    if let style = filterStyle {
                        Text(verbatim: style).opacity(Theme.secondaryOpacity)
                    }
                }
                .font(Theme.sans(Theme.Size.control, .medium))
            }
            .foregroundStyle(Theme.yolk)
            .padding(.horizontal, 24)
            .frame(height: 58)
            .background(Theme.ink.opacity(0.82), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Theme.safeSide)
            .padding(.top, Theme.safeTopBottom)
            .opacity(toolbarShown ? 0 : 1)
            .animation(.easeInOut(duration: GridLook.toolbarFade), value: toolbarShown)
            .accessibilityLabel("Filtered by \(filterStyle.map { "\(genre), \($0)" } ?? genre)")
        }
    }

    // MARK: - Behaviour

    /// Select opens the record. At idle the press only ends the idle state.
    private func select() {
        if idle {
            endIdle()
            return
        }
        guard let release = current else { return }
        onOpen(release)
    }

    private func move(_ direction: MoveCommandDirection) {
        // Any press ends idle, and that press is not acted on.
        if idle {
            endIdle()
            return
        }
        let count = releases.count
        guard count > 0 else {
            if direction == .up { onMoveUp() }
            return
        }
        let column = index % GridMeasures.columns
        var next = index
        switch direction {
        case .left:
            if column > 0 { next = index - 1 }
        case .right:
            if column + 1 < GridMeasures.columns, index + 1 < count { next = index + 1 }
        case .up:
            if index >= GridMeasures.columns {
                next = index - GridMeasures.columns
            } else {
                onMoveUp()
                return
            }
        case .down:
            if index + GridMeasures.columns < count {
                next = index + GridMeasures.columns
            } else if index / GridMeasures.columns < (count - 1) / GridMeasures.columns {
                // Above a short last row: on to the last record.
                next = count - 1
            }
        @unknown default:
            break
        }
        restartIdleTimer()
        guard next != index else { return }
        index = next
        topRow = GridMeasures.topRow(forIndex: next, count: count)
        onBrowse(releases[next].releaseId)
        showScale()
    }

    /// Puts the wall on the record the collection was last on, with its row
    /// second from the top where the ends of the wall allow.
    private func land(animated: Bool) {
        let count = releases.count
        guard count > 0 else {
            index = 0
            topRow = 0
            return
        }
        let wanted = landingID ?? current?.releaseId
        let place = releases.firstIndex { $0.releaseId == wanted } ?? min(index, count - 1)
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            index = place
            topRow = GridMeasures.topRow(forIndex: place, count: count)
        }
        onBrowse(releases[place].releaseId)
    }

    private func showScale() {
        scaleShown = true
        scaleTask?.cancel()
        scaleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(GridLook.scaleStay))
            guard !Task.isCancelled else { return }
            scaleShown = false
        }
    }

    private func hideScale() {
        scaleTask?.cancel()
        scaleShown = false
    }

    /// Counts from the last press. Idle starts after the Gallery's idle time.
    private func restartIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TideTiming.galleryIdle))
            guard !Task.isCancelled, focused else { return }
            hideScale()
            idle = true
        }
    }

    private func cancelIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
        idle = false
    }

    private func endIdle() {
        idle = false
        restartIdleTimer()
    }

    /// The glow behind the wall and the halo's colours, from the sleeve in focus.
    private func refreshColours() async {
        guard let release = current, let url = release.preferredCoverURL,
              let image = try? await ImagePipeline.shared.image(for: url) else { return }
        glowColor = CoverColor.dominant(from: image, releaseId: release.releaseId)
        palette = HaloPalette.sleeve(from: image) ?? .placeholder
    }
}

// MARK: - Measures

/// The Grid's look, in points on a 1920 by 1080 screen, and its timings.
/// Timings the spec marks "to tune" were not tried on a screen.
enum GridLook {
    /// The card's sleeve: a wall sleeve at 1.18 times its size.
    static let cardSleeve: CGFloat = 322
    static let cardMargin: CGFloat = 10
    static let cardCaption: CGFloat = 94
    static let cardSize = CGSize(width: cardSleeve + 2 * cardMargin, height: cardMargin + cardSleeve + cardCaption)
    static let cardRadius: CGFloat = 26
    static let sleeveRadius: CGFloat = 16

    static let toolbarFadeHeight: CGFloat = 260
    static let toolbarFade: TimeInterval = 0.25

    /// The scale sits where the Gallery's does.
    static let scaleTop: CGFloat = 944
    static let scaleFadeTop: CGFloat = 780
    static let scaleFade: TimeInterval = 0.3
    /// Seconds the scale stays after the last press.
    static let scaleStay: TimeInterval = 3

    static let rowGlide: TimeInterval = 0.3
    /// Ink over the wall at idle.
    static let idleDim = 0.74
    static let idleIn: TimeInterval = 3
    static let idleOut: TimeInterval = 0.5
}

/// Where things are in the wall: seven columns edge to edge with 2 pt
/// gutters, four whole rows on screen. Pure arithmetic.
struct GridMeasures: Equatable {
    static let columns = 7
    static let rowsOnScreen = 4
    static let gutter: CGFloat = 2

    let size: CGSize
    let count: Int

    /// A sleeve's side: (1920 − 12) / 7, about 272.6 pt.
    var side: CGFloat {
        (size.width - Self.gutter * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
    }

    var pitch: CGFloat { side + Self.gutter }

    /// Four rows and three gutters are a little taller than the screen; the
    /// overhang is shared between the top and the bottom (8 pt each at 1080).
    var overhang: CGFloat {
        (CGFloat(Self.rowsOnScreen) * side + CGFloat(Self.rowsOnScreen - 1) * Self.gutter - size.height) / 2
    }

    static func rowCount(count: Int) -> Int {
        (max(count, 0) + columns - 1) / columns
    }

    /// The row at the top of the screen when `index` is in focus: the row in
    /// focus is the second of the four, except in the first row and where
    /// the wall stops at its end.
    static func topRow(forIndex index: Int, count: Int) -> Int {
        let row = max(index, 0) / columns
        let last = max(0, rowCount(count: count) - rowsOnScreen)
        return min(max(row - 1, 0), last)
    }

    /// How far the wall is moved up for `topRow`.
    func wallOffset(topRow: Int) -> CGFloat {
        -overhang - CGFloat(topRow) * pitch
    }

    /// The rows worth drawing: those on screen and two beyond each edge.
    func drawnRows(topRow: Int) -> [Int] {
        let last = Self.rowCount(count: count) - 1
        guard last >= 0 else { return [] }
        let from = max(0, topRow - 2)
        let to = min(last, topRow + Self.rowsOnScreen + 1)
        return from <= to ? Array(from...to) : []
    }

    /// The cell of `index` on screen.
    func cellFrame(index: Int, topRow: Int) -> CGRect {
        let column = index % Self.columns
        let row = index / Self.columns - topRow
        return CGRect(x: CGFloat(column) * pitch, y: -overhang + CGFloat(row) * pitch, width: side, height: side)
    }

    /// The card for `index`: its sleeve centred on the cell, then moved
    /// inward so it never crosses the safe area.
    func cardFrame(index: Int, topRow: Int) -> CGRect {
        let cell = cellFrame(index: index, topRow: topRow)
        let card = GridLook.cardSize
        var x = cell.midX - card.width / 2
        var y = cell.midY - GridLook.cardSleeve / 2 - GridLook.cardMargin
        x = min(max(x, Theme.safeSide), size.width - Theme.safeSide - card.width)
        y = min(max(y, Theme.safeTopBottom), size.height - Theme.safeTopBottom - card.height)
        return CGRect(x: x, y: y, width: card.width, height: card.height)
    }
}

// MARK: - Pieces

/// A sleeve in the wall: square, fitted whole on its mat. Until the art has
/// loaded, the cell shows the album's title.
private struct GridTile: View {
    let release: CachedRelease
    let side: CGFloat

    var body: some View {
        ZStack {
            Text(release.title)
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 16)
            FittedSleeve(url: release.preferredCoverURL)
        }
        .frame(width: side, height: side)
        .clipped()
    }
}

/// The card for the sleeve in focus: yolk, with the sleeve, the album title
/// and the artist. At idle it goes dark, with a fine line around it.
private struct GridCard: View {
    let release: CachedRelease
    let idle: Bool

    var body: some View {
        VStack(spacing: 0) {
            FittedSleeve(url: release.preferredCoverURL)
                .frame(width: GridLook.cardSleeve, height: GridLook.cardSleeve)
                .clipShape(RoundedRectangle(cornerRadius: GridLook.sleeveRadius))
                .padding(.top, GridLook.cardMargin)
            VStack(spacing: 0) {
                Text(release.title)
                    .font(Theme.serif(29))
                    .foregroundStyle(idle ? Theme.text : Theme.onYolk)
                    .lineLimit(1)
                    .frame(height: 34)
                Text(release.artistDisplayName)
                    .font(Theme.sans(Theme.Size.small))
                    .foregroundStyle(idle ? Theme.body : Theme.onYolk.opacity(0.72))
                    .lineLimit(1)
                    .frame(height: 30)
            }
            .padding(.top, 13)
            .padding(.horizontal, 8 + GridLook.cardMargin)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(width: GridLook.cardSize.width, height: GridLook.cardSize.height)
        .background(idle ? Theme.surface : Theme.yolk, in: RoundedRectangle(cornerRadius: GridLook.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: GridLook.cardRadius)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
                .opacity(idle ? 1 : 0)
        )
        .shadow(color: .black.opacity(0.75), radius: 45, y: 34)
        .animation(.easeInOut(duration: idle ? GridLook.idleIn : GridLook.idleOut), value: idle)
        .accessibilityHidden(true)
    }
}

/// The matrix over the wall: hairlines down every gutter and along every
/// row, and a tick under every other empty cell. The rows snap, so the lines
/// never move; only the ticks follow the row at the top.
private struct GridMatrix: View {
    let grid: GridMeasures
    let topRow: Int

    var body: some View {
        Canvas { context, size in
            guard grid.side > 0 else { return }
            var lines = Path()
            for column in 1..<GridMeasures.columns {
                let x = CGFloat(column) * grid.pitch - GridMeasures.gutter / 2
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...GridMeasures.rowsOnScreen {
                let y = -grid.overhang + CGFloat(row) * grid.pitch - GridMeasures.gutter / 2
                guard y >= 0, y <= size.height else { continue }
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(Theme.line), lineWidth: 1)

            var ticks = Path()
            for row in 0..<GridMeasures.rowsOnScreen {
                for column in 0..<GridMeasures.columns {
                    let wallRow = topRow + row
                    guard MosaicPlaceholderLayout.isEmpty(
                        row: wallRow,
                        column: column,
                        albumCount: grid.count,
                        columnCount: GridMeasures.columns
                    ), (wallRow + column).isMultiple(of: 2) else { continue }
                    let x = CGFloat(column) * grid.pitch + grid.side / 2
                    let y = -grid.overhang + CGFloat(row) * grid.pitch + grid.side + GridMeasures.gutter / 2
                    ticks.addRect(CGRect(x: x - 0.5, y: y - 4, width: 1, height: 8))
                }
            }
            context.fill(ticks, with: .color(Theme.lineStrong))
        }
        .allowsHitTesting(false)
    }
}

/// Renders only the label: the wall draws its own focus, the yolk card.
private struct GridBareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
