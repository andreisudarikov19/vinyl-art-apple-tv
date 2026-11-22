import SwiftData
import SwiftUI

/// What Settings shows of the record the Gallery was last on: its title and
/// artist over a live scale, as the preview of a scale style.
struct SettingsScalePreview: Equatable {
    let title: String
    let artist: String
    let tape: ScaleTape
    /// The record's place on the tape.
    let index: Int
}

/// How far a refresh of the collection has got, while one runs.
struct SettingsRefreshProgress: Equatable {
    let processed: Int
    let total: Int
}

/// Settings, in full screen (design-handoff/specs/03-settings.md). The rows
/// are on the left; a card on the right explains the row in focus. The scale
/// style and the ambient halo each open a screen of their own, laid out the
/// same way. Menu steps back: from those screens to Settings, and from
/// Settings to the collection.
struct SettingsView: View {
    let accountName: String
    /// Nil when no refresh is running.
    let refreshProgress: SettingsRefreshProgress?
    /// How the last refresh ended, for the few seconds the Gallery keeps it.
    let refreshMessage: String?
    /// Nil when the collection is empty.
    let preview: SettingsScalePreview?
    let startRefresh: () -> Void
    let signOut: (_ erase: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]

    @State private var page: Page = .main
    /// The row the card describes: the one in focus, or the last one that was.
    @State private var described: Stop = .scaleStyle
    @State private var showingAbout = false
    @State private var showingSignOut = false
    @FocusState private var focus: Stop?

    enum Page: Equatable {
        case main, scale, halo
    }

    enum Stop: Hashable {
        case scaleStyle, halo, refresh, signOut, about
        case haloGallery, haloTrackList, haloCover
        case style(ScaleStyle)
    }

    private var haloSettings: HaloSettings {
        preferences.first?.haloSettings ?? HaloSettings()
    }

    private var scaleStyle: ScaleStyle {
        preferences.first?.scaleStyle ?? .slideRule
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsBackground()
            HStack(alignment: .top, spacing: 0) {
                rows
                    .frame(width: SettingsLayout.columnWidth, alignment: .topLeading)
                    .padding(.top, SettingsLayout.columnTop)
                Spacer(minLength: 0)
                card
                    .frame(width: SettingsLayout.cardSize.width, height: SettingsLayout.cardSize.height)
                    .padding(.top, SettingsLayout.cardTop)
            }
            .padding(.horizontal, Theme.safeSide)
            // Behind the dialog nothing takes focus.
            .disabled(showingSignOut)
            if showingSignOut {
                SignOutDialog(accountName: accountName, cancel: closeSignOut, signOut: leave)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: showingSignOut)
        .onExitCommand { handleExit() }
        .onChange(of: focus) { _, stop in
            if let stop { described = stop }
        }
        .onAppear { focusSoon(on: .scaleStyle) }
        .fullScreenCover(isPresented: $showingAbout, onDismiss: { focusSoon(on: .about) }) {
            AboutView()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch page {
        case .main: mainRows
        case .scale: scaleRows
        case .halo: haloRows
        }
    }

    private var mainRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(Theme.serif(Theme.Size.screenTitle))
                .tracking(-Theme.Size.screenTitle * 0.02)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            SettingsSectionLabel("APPEARANCE")
            SettingsRow("Scale style", value: scaleStyle.displayName, showsChevron: true) {
                open(.scale)
            }
            .focused($focus, equals: .scaleStyle)
            SettingsRow("Ambient halo", showsChevron: true) {
                open(.halo)
            }
            .focused($focus, equals: .halo)
            .padding(.top, SettingsLayout.rowGap)
            SettingsSectionLabel("COLLECTION")
            SettingsRow("Refresh collection", value: refreshProgress == nil ? "" : "Updating") {
                if refreshProgress == nil { startRefresh() }
            }
            .focused($focus, equals: .refresh)
            SettingsRow("Sign out", value: accountName) {
                showingSignOut = true
            }
            .focused($focus, equals: .signOut)
            .padding(.top, SettingsLayout.rowGap)
            SettingsSectionLabel("ABOUT")
            SettingsRow("About", showsChevron: true) {
                showingAbout = true
            }
            .focused($focus, equals: .about)
        }
    }

    private var scaleRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: "Scale style",
                line: "Choose how the scale under the cover looks. Every style works the same way."
            )
            ForEach(ScaleStyle.allCases, id: \.self) { style in
                SettingsRow(LocalizedStringKey(style.displayName), value: style == scaleStyle ? "In use" : "", showsTick: style == scaleStyle) {
                    UserPreferences.current(in: modelContext).scaleStyle = style
                }
                .focused($focus, equals: .style(style))
                .padding(.top, style == ScaleStyle.allCases.first ? 0 : SettingsLayout.rowGap)
            }
            Text("More styles will arrive in later versions.")
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .padding(.top, 36)
        }
    }

    private var haloRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(title: "Ambient halo", line: "Choose where the light appears.")
            SettingsRow("Gallery", value: haloSettings.gallery.displayName) {
                changeHalo { $0.gallery = $0.gallery == .on ? .off : .on }
            }
            .focused($focus, equals: .haloGallery)
            SettingsRow("Track list", value: haloSettings.trackList.displayName) {
                changeHalo { $0.trackList = $0.trackList == .on ? .off : .on }
            }
            .focused($focus, equals: .haloTrackList)
            .padding(.top, SettingsLayout.rowGap)
            SettingsRow("Cover view", value: haloSettings.coverView.displayName) {
                changeHalo { $0.cycleCoverView() }
            }
            .focused($focus, equals: .haloCover)
            .padding(.top, SettingsLayout.rowGap)
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardPreview
                .frame(maxWidth: .infinity)
                .frame(height: SettingsLayout.previewHeight)
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .padding(.horizontal, SettingsLayout.cardPadding)
            cardText
                .padding(.horizontal, SettingsLayout.cardPadding)
                .padding(.top, 47)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .animation(.easeInOut(duration: 0.2), value: described)
    }

    @ViewBuilder
    private var cardPreview: some View {
        switch described {
        case .scaleStyle:
            SettingsScalePreviewView(preview: preview, style: scaleStyle)
        case .style(let style):
            SettingsScalePreviewView(preview: preview, style: style)
        case .halo, .haloGallery, .haloTrackList, .haloCover:
            SettingsHaloPicture()
        case .refresh:
            refreshPreview
        case .signOut:
            SettingsNamePreview(eyebrow: "SIGNED IN AS", name: accountName)
        case .about:
            SettingsNamePreview(eyebrow: AppVersion.current.uppercased(), name: "Vinyl for Apple TV")
        }
    }

    /// While a refresh runs: how far it has got. Otherwise: when the
    /// collection was last fetched.
    @ViewBuilder
    private var refreshPreview: some View {
        if let progress = refreshProgress {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(progress.total > 0 ? "\(progress.processed) / \(progress.total)" : "\(progress.processed)")
                        .font(Theme.mono(Theme.Size.reading, medium: true))
                        .foregroundStyle(Theme.yolk)
                    Text("RECORDS")
                        .font(Theme.mono(Theme.Size.small))
                        .tracking(Theme.Size.small * Theme.eyebrowTracking)
                        .foregroundStyle(Theme.quiet)
                }
                SettingsProgressBar(share: progress.total > 0 ? Double(progress.processed) / Double(progress.total) : 0)
                Text("You can leave Settings and keep browsing. New records appear as they arrive.")
                    .font(Theme.sans(Theme.Size.small))
                    .foregroundStyle(Theme.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SettingsLayout.cardPadding)
        } else if let refreshMessage {
            Text(refreshMessage)
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SettingsLayout.cardPadding)
        } else if let last = preferences.first?.lastSyncDate {
            VStack(spacing: 14) {
                Text("LAST FETCHED")
                    .font(Theme.mono(Theme.Size.small))
                    .tracking(Theme.Size.small * Theme.eyebrowTracking)
                    .foregroundStyle(Theme.quiet)
                Text(last, format: .dateTime.day().month(.wide).year().hour().minute())
                    .font(Theme.serif(Theme.Size.cardTitle))
                    .foregroundStyle(Theme.text)
            }
        } else {
            SettingsNamePreview(eyebrow: "LAST FETCHED", name: "Not yet")
        }
    }

    @ViewBuilder
    private var cardText: some View {
        switch described {
        case .scaleStyle:
            SettingsCardText(
                eyebrow: "APPEARANCE",
                title: "Scale style",
                text: "The scale under the cover shows where you are in your collection. Choose how it looks. Every style works the same way.",
                hint: "Press Select to choose a style."
            )
        case .halo:
            SettingsCardText(
                eyebrow: "APPEARANCE",
                title: "Ambient halo",
                text: "Slow light in the colours of the sleeve: a tide in the Gallery and on the track list, a lava lamp in the cover view. Each can be set separately.",
                hint: "Press Select to open."
            )
        case .refresh:
            SettingsCardText(
                eyebrow: "COLLECTION",
                title: "Refresh collection",
                text: "Fetches the current state of your Discogs collection: new records, removed records and changed details.",
                hint: refreshProgress == nil ? "Press Select to start." : "A refresh is running. It cannot be stopped."
            )
        case .signOut:
            SettingsCardText(
                eyebrow: "COLLECTION",
                title: "Sign out",
                text: "Signs this Apple TV out of your Discogs account.",
                hint: "Press Select to choose what happens to the library."
            )
        case .about:
            SettingsCardText(
                eyebrow: "ABOUT",
                title: "About",
                text: "The version of the app, its privacy policy, and where to get help.",
                hint: "Press Select to open."
            )
        case .style(let style):
            SettingsCardText(
                eyebrow: style.eyebrow,
                title: style.displayName,
                text: style.note,
                hint: "The preview follows the record you were last looking at."
            )
        case .haloGallery:
            SettingsChoicesText(
                eyebrow: "IN THE GALLERY",
                title: "Gallery",
                choices: [
                    .init(name: "On", text: "After half a minute without a press, the toolbar fades and the sleeve's colour swells and draws back behind the cover, like a tide.", isCurrent: haloSettings.gallery == .on),
                    .init(name: "Off", text: "The Gallery stays as it is.", isCurrent: haloSettings.gallery == .off),
                ]
            )
        case .haloTrackList:
            SettingsChoicesText(
                eyebrow: "ON THE TRACK LIST",
                title: "Track list",
                choices: [
                    .init(name: "On", text: "After 15 seconds without a press, the sleeve's colour moves in from the top left corner and draws back, like a tide.", isCurrent: haloSettings.trackList == .on),
                    .init(name: "Off", text: "The background stays still.", isCurrent: haloSettings.trackList == .off),
                ]
            )
        case .haloCover:
            SettingsChoicesText(
                eyebrow: "IN THE COVER VIEW",
                title: "Cover view",
                choices: [
                    .init(name: "On", text: "The light is always there.", isCurrent: haloSettings.coverView == .on),
                    .init(name: "Off", text: "The sleeve alone, on black.", isCurrent: haloSettings.coverView == .off),
                    .init(name: "Manual", text: "Left and Right on the remote turn the light off and on.", isCurrent: haloSettings.coverView == .manual),
                ]
            )
        }
    }

    // MARK: - Behaviour

    /// What Menu does. In the sign-out dialog it is the same as Cancel; on a
    /// screen inside Settings it steps back; on the main screen it closes
    /// Settings. The handler is always in place and closes Settings itself:
    /// one that was only switched on inside a screen was not picked up, and
    /// Menu there closed all of Settings.
    private func handleExit() {
        if showingSignOut {
            closeSignOut()
        } else if page != .main {
            open(.main)
        } else {
            dismiss()
        }
    }

    /// Closes the sign-out dialog and puts focus back on its row.
    private func closeSignOut() {
        showingSignOut = false
        focusSoon(on: .signOut)
    }

    /// Moves to another screen of Settings and puts focus on its first row,
    /// or back on the row that opened it.
    private func open(_ next: Page) {
        let from = page
        page = next
        switch next {
        case .scale: focusSoon(on: .style(scaleStyle))
        case .halo: focusSoon(on: .haloGallery)
        case .main: focusSoon(on: from == .halo ? .halo : .scaleStyle)
        }
    }

    /// Puts focus on a row once the screen has settled, so it is always
    /// visibly somewhere.
    private func focusSoon(on stop: Stop) {
        described = stop
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focus = stop
        }
    }

    /// Stores a change to the three halo switches.
    private func changeHalo(_ change: (inout HaloSettings) -> Void) {
        var settings = haloSettings
        change(&settings)
        UserPreferences.current(in: modelContext).haloSettings = settings
    }

    /// Closes Settings, then signs out, so it does not stay over the
    /// sign-in screen.
    private func leave(erasing: Bool) {
        showingSignOut = false
        dismiss()
        signOut(erasing)
    }
}

// MARK: - Names and notes

extension ScaleStyle {
    var displayName: String {
        switch self {
        case .slideRule: "Slide rule"
        case .glassLens: "Glass lens"
        }
    }

    /// The line over the style's name on its card. Eras and countries only,
    /// never brands.
    var eyebrow: String {
        switch self {
        case .slideRule: "FROM THE LATE 1930S"
        case .glassLens: "A LENS OVER THE NEEDLE"
        }
    }

    var note: String {
        switch self {
        case .slideRule:
            "The classic straight radio scale. Radios with several wavebands favoured it, because every band could have a scale of the same length."
        case .glassLens:
            "A small glass lens rides over the needle and enlarges the part of the scale beneath it."
        }
    }
}

extension HaloSettings.Switch {
    var displayName: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        }
    }
}

extension HaloSettings.CoverMode {
    var displayName: String {
        switch self {
        case .on: "On"
        case .off: "Off"
        case .manual: "Manual"
        }
    }
}

// MARK: - Pieces

/// The measures of the Settings screens, in points on a 1920 by 1080 screen.
private enum SettingsLayout {
    static let columnTop: CGFloat = 96
    static let columnWidth: CGFloat = 720
    static let rowGap: CGFloat = 12
    static let rowPadding: CGFloat = 36
    static let cardTop: CGFloat = 120
    static let cardSize = CGSize(width: 940, height: 840)
    static let cardPadding: CGFloat = 64
    static let previewHeight: CGFloat = 400
}

/// Ink, with a faint warm glow from the top right, behind the card. The
/// About screen stands on it too.
struct SettingsBackground: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(
                colors: [Color(hex: 0x2A1C14), Theme.ink],
                center: UnitPoint(x: 0.7, y: 0.25),
                startRadius: 0,
                endRadius: 1100
            )
        }
        .ignoresSafeArea()
    }
}

/// "APPEARANCE": DM Mono 25, tracked, quiet, 36 pt in, with 28 pt above and
/// 12 pt below.
private struct SettingsSectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.mono(Theme.Size.small))
            .tracking(Theme.Size.small * Theme.eyebrowTracking)
            .foregroundStyle(Theme.quiet)
            .padding(.leading, SettingsLayout.rowPadding)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The head of a screen inside Settings: a "SETTINGS" eyebrow, the title in
/// Fraunces 76, and a line under it.
private struct SettingsPageHeader: View {
    let title: LocalizedStringKey
    let line: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(Theme.mono(Theme.Size.small))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.quiet)
            Text(title)
                .font(Theme.serif(Theme.Size.screenTitle))
                .tracking(-Theme.Size.screenTitle * 0.02)
                .foregroundStyle(Theme.text)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(line)
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.body)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.bottom, 40)
        }
    }
}

/// One row of Settings: an 84 pt pill with its name on the left and its
/// value, a tick or a chevron on the right. Yolk in focus.
private struct SettingsRow: View {
    let title: LocalizedStringKey
    var value: String = ""
    var showsChevron = false
    var showsTick = false
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        value: String = "",
        showsChevron: Bool = false,
        showsTick: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.showsChevron = showsChevron
        self.showsTick = showsTick
        self.action = action
    }

    var body: some View {
        // The style draws the whole row, so it can read focus the way the
        // toolbar's controls do.
        Button(action: action) { Text(title) }
            .buttonStyle(SettingsRowStyle(title: title, value: value, showsChevron: showsChevron, showsTick: showsTick))
    }
}

private struct SettingsRowStyle: ButtonStyle {
    let title: LocalizedStringKey
    let value: String
    let showsChevron: Bool
    let showsTick: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsRowLabel(title: title, value: value, showsChevron: showsChevron, showsTick: showsTick)
    }
}

private struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let value: String
    let showsChevron: Bool
    let showsTick: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(Theme.sans(Theme.Size.control, isFocused ? .semibold : .medium))
                .foregroundStyle(isFocused ? Theme.onYolk : Theme.text)
            Spacer(minLength: 16)
            if showsTick {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)
            }
            if !value.isEmpty {
                Text(value)
                    .font(Theme.mono(Theme.Size.small, medium: isFocused))
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isFocused ? Theme.onYolk : Theme.quiet)
        .padding(.horizontal, SettingsLayout.rowPadding)
        .frame(height: Theme.rowHeight)
        .frame(maxWidth: .infinity)
        .background {
            if isFocused {
                Capsule().fill(Theme.yolk)
            } else {
                Capsule()
                    .fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
        }
        .contentShape(Capsule())
    }
}

/// The sign-out dialog: one question, with Cancel in focus when it opens, so
/// a stray press never signs out and erasing takes two deliberate moves.
private struct SignOutDialog: View {
    let accountName: String
    let cancel: () -> Void
    let signOut: (_ erase: Bool) -> Void

    private enum Choice: Hashable {
        case cancel, keep, erase
    }

    @FocusState private var focus: Choice?

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.78)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("Sign out of Discogs?")
                    .font(Theme.serif(Theme.Size.albumTitle))
                    .tracking(-Theme.Size.albumTitle * 0.02)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("You are signed in as \(accountName). Your library can stay on this Apple TV, ready for the next time you sign in, or be erased now.")
                    .font(Theme.sans(Theme.Size.control))
                    .foregroundStyle(Theme.body)
                    .lineSpacing(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                VStack(spacing: 20) {
                    Button("Cancel", action: cancel)
                        .buttonStyle(SignOutButtonStyle(title: "Cancel", isDanger: false))
                        .focused($focus, equals: .cancel)
                    Button("Sign out and keep library") { signOut(false) }
                        .buttonStyle(SignOutButtonStyle(title: "Sign out and keep library", isDanger: false))
                        .focused($focus, equals: .keep)
                    Button("Sign out and erase library") { signOut(true) }
                        .buttonStyle(SignOutButtonStyle(title: "Sign out and erase library", isDanger: true))
                        .focused($focus, equals: .erase)
                }
                .padding(.top, 36)
                Text("Erasing removes the library from this Apple TV. It cannot be undone.")
                    .font(Theme.sans(Theme.Size.small))
                    .foregroundStyle(Theme.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }
            .padding(.top, 56)
            .padding(.horizontal, 64)
            .padding(.bottom, 48)
            .frame(width: 920)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.lineStrong, lineWidth: 1))
        }
        .defaultFocus($focus, .cancel)
        .onAppear {
            // Cancel is in focus when the dialog opens, whatever tvOS would
            // have picked.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                focus = .cancel
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// A button of the sign-out dialog: an 84 pt pill, yolk in focus. The one
/// that erases is in the danger colour: outlined at rest, filled in focus.
private struct SignOutButtonStyle: ButtonStyle {
    let title: LocalizedStringKey
    let isDanger: Bool

    func makeBody(configuration: Configuration) -> some View {
        SignOutButtonLabel(title: title, isDanger: isDanger)
    }
}

private struct SignOutButtonLabel: View {
    let title: LocalizedStringKey
    let isDanger: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(Theme.sans(Theme.Size.control, isFocused ? .semibold : .medium))
            .foregroundStyle(isFocused ? Theme.onYolk : isDanger ? Theme.danger : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.rowHeight)
            .background {
                if isFocused {
                    Capsule().fill(isDanger ? Theme.danger : Theme.yolk)
                } else {
                    Capsule()
                        .fill(Theme.surface)
                        .overlay(Capsule().strokeBorder(isDanger ? Theme.danger.opacity(0.45) : Theme.line, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
    }
}

/// The card's text for a row: a yolk eyebrow, a Fraunces title, the
/// explanation and a quiet hint.
private struct SettingsCardText: View {
    let eyebrow: String
    let title: String
    let text: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeading(eyebrow: eyebrow, title: title)
            Text(text)
                .font(Theme.sans(Theme.Size.control))
                .foregroundStyle(Theme.body)
                .lineSpacing(12)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Text(hint)
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
        }
    }
}

private struct SettingsCardHeading: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(Theme.mono(Theme.Size.small, medium: true))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.yolk)
            Text(title)
                .font(Theme.serif(Theme.Size.cardTitle))
                .tracking(-Theme.Size.cardTitle * 0.02)
                .foregroundStyle(Theme.text)
                .padding(.top, 14)
        }
    }
}

/// The card's text for a halo switch: its choices, each with what it does,
/// and a yolk tick on the one in use.
private struct SettingsChoicesText: View {
    struct Choice: Identifiable {
        let name: String
        let text: String
        let isCurrent: Bool
        var id: String { name }
    }

    let eyebrow: String
    let title: String
    let choices: [Choice]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeading(eyebrow: eyebrow, title: title)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(choices) { choice in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.yolk)
                            .opacity(choice.isCurrent ? 1 : 0)
                            .frame(width: 40, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(choice.name)
                            .font(Theme.sans(Theme.Size.control, choice.isCurrent ? .semibold : .regular))
                            .foregroundStyle(choice.isCurrent ? Theme.text : Theme.body)
                            .frame(width: 134, alignment: .leading)
                        Text(choice.text)
                            .font(Theme.sans(Theme.Size.small))
                            .foregroundStyle(Theme.body)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 20)
            Text("Press Select to change.")
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .padding(.top, 24)
        }
    }
}

/// The preview of a scale style: the last record's title and artist over a
/// live scale in that style, at two thirds of its size to fit the card.
private struct SettingsScalePreviewView: View {
    let preview: SettingsScalePreview?
    let style: ScaleStyle

    private let shrink: CGFloat = 0.66

    var body: some View {
        if let preview {
            VStack(spacing: 0) {
                Text(preview.title)
                    .font(Theme.serif(Theme.Size.albumTitle))
                    .tracking(-Theme.Size.albumTitle * 0.02)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(preview.artist)
                    .font(Theme.sans(Theme.Size.control))
                    .foregroundStyle(Theme.body)
                    .lineLimit(1)
                    .padding(.top, 4)
                scale(preview)
                    .frame(width: SlideRuleScale.size.width, height: SlideRuleScale.size.height)
                    .scaleEffect(shrink)
                    .frame(width: SlideRuleScale.size.width * shrink, height: SlideRuleScale.size.height * shrink)
                    .padding(.top, 36)
            }
            .padding(.horizontal, SettingsLayout.cardPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A preview of the scale")
        } else {
            Text("The preview appears once the collection has records.")
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
        }
    }

    @ViewBuilder
    private func scale(_ preview: SettingsScalePreview) -> some View {
        switch style {
        case .slideRule:
            SlideRuleScale(tape: preview.tape, current: preview.index, total: preview.tape.groups.count, idle: false)
        case .glassLens:
            GlassLensScale(tape: preview.tape, current: preview.index, total: preview.tape.groups.count, idle: false)
        }
    }
}

/// A small picture of a sleeve with light behind it, between dimmed sleeves.
/// Flat colours only; no artwork.
private struct SettingsHaloPicture: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(hex: 0xC8742E))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .opacity(0.7)
            HStack(spacing: 36) {
                side(Color(hex: 0x2E3554))
                side(Color(hex: 0x8A7560))
                Rectangle()
                    .fill(Color(hex: 0xA5523A))
                    .frame(width: 240, height: 240)
                    .padding(.horizontal, 8)
                side(Color(hex: 0x8D8078))
                side(Color(hex: 0x2B2D27))
            }
        }
        .accessibilityHidden(true)
    }

    private func side(_ colour: Color) -> some View {
        Rectangle()
            .fill(colour)
            .frame(width: 80, height: 210)
            .opacity(0.85)
    }
}

/// A quiet line over a name in Fraunces, centred: who is signed in, or the
/// app and its version.
private struct SettingsNamePreview: View {
    let eyebrow: String
    let name: String

    var body: some View {
        VStack(spacing: 14) {
            Text(eyebrow)
                .font(Theme.mono(Theme.Size.small))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.quiet)
            Text(name)
                .font(Theme.serif(Theme.Size.cardTitle))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, SettingsLayout.cardPadding)
    }
}

/// The refresh's progress: an 8 pt bar, yolk on a line.
private struct SettingsProgressBar: View {
    /// 0 to 1.
    let share: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.lineStrong)
                Capsule()
                    .fill(Theme.yolk)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, share))))
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.3), value: share)
        .accessibilityHidden(true)
    }
}
