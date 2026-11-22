import SwiftUI

// The one toolbar for the gallery: sort and genre on the left, what to do on
// the right. Spec: design-handoff/specs/02-toolbar.md. Every control has a
// fixed slot, so a label that changes never moves its neighbours.

// MARK: - Focus, menus and their rules

/// Every stop on the toolbar. Menu rows are stops too, so focus can land on
/// the current choice when a menu opens.
enum ToolbarFocus: Hashable {
    case sort, genre, suggest, view, settings
    case sortRow(GallerySort)
    case genreRow(String?) // nil is "All genres"
    case styleRow(String?) // nil is "All <genre>"

    /// The control a stop belongs to. Up from the cover returns to it.
    var control: ToolbarFocus {
        switch self {
        case .sortRow: .sort
        case .genreRow, .styleRow: .genre
        default: self
        }
    }
}

/// The two menus. Each opens from its control.
enum ToolbarMenu: Hashable {
    case sort, genre
}

/// The rules behind the menus, free of views so they can be tested.
enum ToolbarRules {
    /// Where focus lands when a menu opens: on the current choice. A genre
    /// menu opened with a style in use lands on that style, in its column.
    static func openFocus(for menu: ToolbarMenu, sort: GallerySort, filter: GalleryFilter?) -> ToolbarFocus {
        switch menu {
        case .sort:
            return .sortRow(sort)
        case .genre:
            if let style = filter?.style { return .styleRow(style) }
            return .genreRow(filter?.genre)
        }
    }

    /// The genre whose style column is already open when the genre menu opens.
    static func openStyleGenre(for filter: GalleryFilter?) -> String? {
        guard let filter, filter.style != nil else { return nil }
        return filter.genre
    }
}

/// Fixed widths of the toolbar's slots, in points (spec 02, Layout).
enum ToolbarSize {
    static let sort: CGFloat = 330
    static let genre: CGFloat = 440
    static let suggest: CGFloat = 212
    static let view: CGFloat = 160
    static let settings: CGFloat = 86
    /// Where the menus open: 12 pt below the toolbar.
    static let menuTop: CGFloat = Theme.safeTopBottom + Theme.controlHeight + Theme.controlGap
}

// MARK: - Looks

/// The four looks of a control, given to its label through the environment.
enum ToolbarLook {
    case rest, filtered, focused, menu

    /// The colour of the control's text and icons.
    var tint: Color {
        switch self {
        case .rest: Theme.body
        case .filtered: Theme.yolk
        case .focused: Theme.onYolk
        case .menu: Theme.text
        }
    }
}

private struct ToolbarLookKey: EnvironmentKey {
    static let defaultValue: ToolbarLook = .rest
}

extension EnvironmentValues {
    var toolbarLook: ToolbarLook {
        get { self[ToolbarLookKey.self] }
        set { self[ToolbarLookKey.self] = newValue }
    }
}

/// The pill behind a control: yolk when focused, a surface with a thin
/// outline while its menu is open, nothing at rest.
private struct ToolbarPill: View {
    let look: ToolbarLook

    var body: some View {
        switch look {
        case .focused:
            Capsule().fill(Theme.yolk)
        case .menu:
            Capsule()
                .fill(Theme.surface)
                .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 2))
        case .rest, .filtered:
            Color.clear
        }
    }
}

/// A control's slot: a fixed width, the pill, and the label inside 28 pt of
/// padding. Its look follows focus and whether its menu is open.
private struct ToolbarSlot<Label: View>: View {
    let width: CGFloat
    var menuOpen = false
    var filtered = false
    var centered = false
    let label: Label

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let look: ToolbarLook = menuOpen ? .menu : isFocused ? .focused : filtered ? .filtered : .rest
        label
            .environment(\.toolbarLook, look)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, Theme.controlPadding)
            .frame(width: width, height: Theme.controlHeight)
            .background { ToolbarPill(look: look) }
            .contentShape(Capsule())
    }
}

/// The look of a toolbar control. Also used for the Settings menu's button.
struct ToolbarButtonStyle: ButtonStyle {
    let width: CGFloat
    var menuOpen = false
    var filtered = false
    var centered = false

    func makeBody(configuration: Configuration) -> some View {
        ToolbarSlot(
            width: width,
            menuOpen: menuOpen,
            filtered: filtered,
            centered: centered,
            label: configuration.label
        )
    }
}

// MARK: - Labels

/// Icon, 12 pt gap, title. Inter 29 pt: Medium at rest, Semibold in focus.
private struct IconTitle: View {
    let systemImage: String
    let title: String

    @Environment(\.toolbarLook) private var look

    var body: some View {
        HStack(spacing: Theme.controlGap) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .frame(width: 28, height: 28)
            Text(title)
                .font(Theme.sans(Theme.Size.control, look == .focused ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(look.tint)
    }
}

/// The genre control's text: "All genres", "Electronic", or "Electronic: Ambient"
/// with the style at 65% of the same colour.
private struct GenreTitle: View {
    let genre: String?
    let style: String?

    @Environment(\.toolbarLook) private var look

    private var text: Text {
        let head = Text(genre ?? "All genres").foregroundColor(look.tint)
        guard let style else { return head }
        return head + Text(": \(style)").foregroundColor(look.tint.opacity(Theme.secondaryOpacity))
    }

    var body: some View {
        HStack(spacing: Theme.controlGap) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 28))
                .frame(width: 28, height: 28)
            text
                .font(Theme.sans(Theme.Size.control, look == .focused ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(look.tint)
    }
}

/// The Gallery glyph: a tall sleeve between two thin ones, as in the
/// reference. Drawn in a 30 pt square.
private struct GalleryGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 9, y: 4, width: 12, height: 22), cornerSize: CGSize(width: 2, height: 2))
        for x in [CGFloat(3), 27] {
            path.move(to: CGPoint(x: x, y: 9))
            path.addLine(to: CGPoint(x: x, y: 21))
        }
        return path
    }
}

/// One of the two icons in the view switch, with a yolk underline when it is
/// the current view.
private struct ViewChoice<Icon: View>: View {
    let isCurrent: Bool
    @ViewBuilder let icon: Icon

    @Environment(\.toolbarLook) private var look

    var body: some View {
        VStack(spacing: 6) {
            icon
                .frame(width: 30, height: 30)
                .foregroundStyle(look.tint.opacity(isCurrent ? 1 : 0.55))
            Rectangle()
                .fill(isCurrent ? (look == .focused ? Theme.onYolk : Theme.yolk) : .clear)
                .frame(width: 30, height: 3)
        }
    }
}

/// One row of a menu: a tick column, the title, a count and, for a genre with
/// styles, a chevron. Focus fills the row in yolk; a genre whose style column
/// is open keeps a thin outline.
private struct MenuRow: View {
    let title: String
    var count: Int?
    var hasStyles = false
    let isCurrent: Bool
    var isStyleParent = false
    let focus: FocusState<ToolbarFocus?>.Binding
    let stop: ToolbarFocus
    var onMoveRight: (() -> Void)?
    var onMoveLeft: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowContent(title: title, count: count, hasStyles: hasStyles, isCurrent: isCurrent)
        }
        .buttonStyle(MenuRowStyle(isStyleParent: isStyleParent))
        .focused(focus, equals: stop)
        .onMoveCommand { direction in
            switch direction {
            case .right: onMoveRight?()
            case .left: onMoveLeft?()
            default: break
            }
        }
    }
}

private struct MenuRowContent: View {
    let title: String
    let count: Int?
    let hasStyles: Bool
    let isCurrent: Bool

    @Environment(\.toolbarLook) private var look

    var body: some View {
        let ink = look == .focused ? Theme.onYolk : Theme.text
        HStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: Theme.Size.small, weight: .semibold))
                .frame(width: 26)
                .opacity(isCurrent ? 1 : 0)
            Text(title)
                .font(Theme.sans(Theme.Size.control, .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 16)
            if let count {
                Text("\(count)")
                    .font(Theme.mono(Theme.Size.small))
                    .foregroundStyle(look == .focused ? Theme.onYolk : Theme.quiet)
            }
            if hasStyles {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 26)
            }
        }
        .foregroundStyle(ink)
    }
}

private struct MenuRowStyle: ButtonStyle {
    var isStyleParent = false

    func makeBody(configuration: Configuration) -> some View {
        MenuRowChrome(isStyleParent: isStyleParent, label: configuration.label)
    }
}

private struct MenuRowChrome<Label: View>: View {
    let isStyleParent: Bool
    let label: Label

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let look: ToolbarLook = isFocused ? .focused : isStyleParent ? .menu : .rest
        label
            .environment(\.toolbarLook, look)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight, maxHeight: Theme.controlHeight, alignment: .leading)
            .background { ToolbarPill(look: look) }
            .contentShape(Capsule())
    }
}

/// A menu's panel: surface, a thin outline, 28 pt corners, 12 pt inside.
private struct ToolbarPanel<Content: View>: View {
    let width: CGFloat
    var height: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 4) {
            content
        }
        .padding(12)
        .frame(width: width, height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 2))
    }
}

// MARK: - Icon controls for the rest of the screen

// MARK: - The toolbar

struct GalleryToolbar<Settings: View>: View {
    let releases: [CachedRelease]
    @Binding var sort: GallerySort
    @Binding var filter: GalleryFilter?
    @Binding var layout: GalleryLayout
    @Binding var menu: ToolbarMenu?
    let focus: FocusState<ToolbarFocus?>.Binding
    let suggest: () -> Void
    let settings: Settings

    /// The genre whose style column is open, if any.
    @State private var styleGenre: String?
    /// Read when the genre menu opens, so its counts are current then.
    @State private var genres: [GenreOption] = []

    init(
        releases: [CachedRelease],
        sort: Binding<GallerySort>,
        filter: Binding<GalleryFilter?>,
        layout: Binding<GalleryLayout>,
        menu: Binding<ToolbarMenu?>,
        focus: FocusState<ToolbarFocus?>.Binding,
        suggest: @escaping () -> Void,
        @ViewBuilder settings: () -> Settings
    ) {
        self.releases = releases
        _sort = sort
        _filter = filter
        _layout = layout
        _menu = menu
        self.focus = focus
        self.suggest = suggest
        self.settings = settings()
    }

    private var hasLibrary: Bool { !releases.isEmpty }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if menu != nil {
                Theme.ink.opacity(0.55)
                    .ignoresSafeArea()
            }
            topFade
            bar
            if let menu {
                menuLayer(menu)
                    .onExitCommand { close(to: menu.control) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    /// Ink at 85% fading to clear over the top 160 pt, behind the bar.
    private var topFade: some View {
        LinearGradient(
            colors: [Theme.ink.opacity(0.85), Theme.ink.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 160)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.controlGap) {
                if hasLibrary {
                    sortButton
                    genreButton
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.controlGap) {
                if hasLibrary {
                    suggestButton
                    viewButton
                }
                settings
            }
        }
        .padding(.horizontal, Theme.safeSide)
        .padding(.top, Theme.safeTopBottom)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // A menu is open: the other controls are not stops until it closes.
    private func isLocked(_ control: ToolbarMenu) -> Bool {
        menu != nil && menu != control
    }

    private var sortButton: some View {
        Button {
            toggle(.sort)
        } label: {
            IconTitle(systemImage: "arrow.up.arrow.down", title: sort.displayName)
        }
        .buttonStyle(ToolbarButtonStyle(width: ToolbarSize.sort, menuOpen: menu == .sort))
        .focused(focus, equals: .sort)
        .disabled(isLocked(.sort))
        .accessibilityLabel("Sort: \(sort.displayName)")
    }

    private var genreButton: some View {
        Button {
            toggle(.genre)
        } label: {
            GenreTitle(genre: filter?.genre, style: filter?.style)
        }
        .buttonStyle(ToolbarButtonStyle(
            width: ToolbarSize.genre,
            menuOpen: menu == .genre,
            filtered: filter != nil
        ))
        .focused(focus, equals: .genre)
        .disabled(isLocked(.genre))
        .accessibilityLabel(filter.map { "Genre: \($0.genre)\($0.style.map { ": \($0)" } ?? "")" } ?? "Genre: All genres")
    }

    private var suggestButton: some View {
        Button(action: suggest) {
            IconTitle(systemImage: "sparkle", title: "Suggest")
        }
        .buttonStyle(ToolbarButtonStyle(width: ToolbarSize.suggest))
        .focused(focus, equals: .suggest)
        .disabled(menu != nil)
    }

    private var viewButton: some View {
        Button {
            layout = layout == .grid ? .coverFlow : .grid
            focusSoon(.view)
        } label: {
            HStack(spacing: 30) {
                ViewChoice(isCurrent: layout != .grid) {
                    GalleryGlyph().stroke(lineWidth: 2)
                }
                ViewChoice(isCurrent: layout == .grid) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 30))
                }
            }
        }
        .buttonStyle(ToolbarButtonStyle(width: ToolbarSize.view, centered: true))
        .focused(focus, equals: .view)
        .disabled(menu != nil)
        .accessibilityLabel("View: \(layout == .grid ? "Grid" : "Gallery"). Select to switch.")
    }

    // MARK: Menus

    @ViewBuilder
    private func menuLayer(_ open: ToolbarMenu) -> some View {
        switch open {
        case .sort:
            sortPanel
                .padding(.leading, Theme.safeSide)
                .padding(.top, ToolbarSize.menuTop)
        case .genre:
            genrePanel
                .padding(.leading, Theme.safeSide + ToolbarSize.sort + Theme.controlGap)
                .padding(.top, ToolbarSize.menuTop)
            if let styleGenre, let option = genres.first(where: { $0.name == styleGenre }) {
                stylePanel(for: option)
                    .padding(.leading, Theme.safeSide + ToolbarSize.sort + Theme.controlGap + 520 + Theme.controlGap)
                    .padding(.top, ToolbarSize.menuTop)
            }
        }
    }

    private var sortPanel: some View {
        ToolbarPanel(width: 400) {
            ForEach(GallerySort.allCases, id: \.self) { option in
                MenuRow(
                    title: option.displayName,
                    isCurrent: sort == option,
                    focus: focus,
                    stop: .sortRow(option)
                ) {
                    sort = option
                    close(to: .sort)
                }
            }
        }
    }

    /// Spec: 520 wide, from the bottom of the toolbar to the bottom safe line,
    /// its last 90 pt fading out.
    private var genrePanel: some View {
        ToolbarPanel(width: 520, height: 1020 - ToolbarSize.menuTop) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    MenuRow(
                        title: "All genres",
                        count: releases.count,
                        isCurrent: filter == nil,
                        focus: focus,
                        stop: .genreRow(nil)
                    ) {
                        choose(genre: nil)
                    }
                    ForEach(genres) { option in
                        MenuRow(
                            title: option.name,
                            count: option.count,
                            hasStyles: !option.styles.isEmpty,
                            isCurrent: filter?.genre == option.name,
                            isStyleParent: styleGenre == option.name,
                            focus: focus,
                            stop: .genreRow(option.name),
                            onMoveRight: option.styles.isEmpty ? nil : { openStyles(option) }
                        ) {
                            choose(genre: option.name)
                        }
                    }
                }
            }
        }
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
        }
    }

    private func stylePanel(for option: GenreOption) -> some View {
        ToolbarPanel(width: 460) {
            MenuRow(
                title: "All \(option.name)",
                count: option.count,
                isCurrent: filter?.genre == option.name && filter?.style == nil,
                focus: focus,
                stop: .styleRow(nil),
                onMoveLeft: { closeStyles(to: option.name) }
            ) {
                choose(genre: option.name, style: nil)
            }
            ForEach(option.styles) { style in
                MenuRow(
                    title: style.name,
                    count: style.count,
                    isCurrent: filter?.genre == option.name && filter?.style == style.name,
                    focus: focus,
                    stop: .styleRow(style.name),
                    onMoveLeft: { closeStyles(to: option.name) }
                ) {
                    choose(genre: option.name, style: style.name)
                }
            }
        }
    }

    // MARK: Actions

    private func toggle(_ target: ToolbarMenu) {
        if menu == target {
            close(to: target.control)
            return
        }
        if target == .genre {
            genres = GalleryArranger.genreOptions(releases)
        }
        styleGenre = ToolbarRules.openStyleGenre(for: filter)
        menu = target
        focusSoon(ToolbarRules.openFocus(for: target, sort: sort, filter: filter))
    }

    private func openStyles(_ option: GenreOption) {
        styleGenre = option.name
        let current = filter?.genre == option.name ? filter?.style : nil
        focusSoon(.styleRow(current))
    }

    private func closeStyles(to genre: String) {
        styleGenre = nil
        focusSoon(.genreRow(genre))
    }

    private func choose(genre: String?) {
        filter = genre.map { GalleryFilter(genre: $0, style: nil) }
        close(to: .genre)
    }

    private func choose(genre: String, style: String?) {
        filter = GalleryFilter(genre: genre, style: style)
        close(to: .genre)
    }

    /// Closes the open menu without a change, or with one, and leaves focus on
    /// the control that opened it.
    private func close(to control: ToolbarFocus) {
        menu = nil
        styleGenre = nil
        focusSoon(control)
    }

    /// Puts focus on a stop once SwiftUI has laid out what it names.
    private func focusSoon(_ stop: ToolbarFocus) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            focus.wrappedValue = stop
        }
    }
}

private extension ToolbarMenu {
    /// The control that opens this menu.
    var control: ToolbarFocus {
        switch self {
        case .sort: .sort
        case .genre: .genre
        }
    }
}
