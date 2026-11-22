import NukeUI
import SwiftData
import SwiftUI

struct GalleryView: View {
    let authenticator: DiscogsAuthenticator
    let client: DiscogsClient

    @Query(sort: \CachedRelease.dateAdded, order: .reverse)
    private var releases: [CachedRelease]
    @Query private var preferences: [UserPreferences]

    @State private var layout: GalleryLayout = .coverFlow
    @State private var sort: GallerySort = .recentlyAdded
    @State private var filter: GalleryFilter?
    @State private var menu: ToolbarMenu?
    @State private var reveal: CoverReveal?
    /// The record under the needle in the cover flow; a sort or filter change keeps it there.
    @State private var browsedReleaseID: Int?
    /// The toolbar stop used last. Up from the cover, and Menu, return to it.
    @State private var lastToolbarStop: ToolbarFocus = .sort
    @Environment(\.modelContext) private var modelContext
    @State private var selected: CachedRelease?
    /// The record on screen was opened by Suggest: it carries the "Another
    /// suggestion" sticker. A record opened from the collection does not.
    @State private var openedBySuggest = false
    @State private var refresh: RefreshState = .idle
    /// The tide is moving: the toolbar fades out behind it.
    @State private var tideEngaged = false
    @State private var showingSettings = false
    @FocusState private var toolbarFocus: ToolbarFocus?

    private enum RefreshState: Equatable {
        case idle
        case running(processed: Int, total: Int)
        case done(stored: Int)
        case failed(message: String)
    }

    /// The browsed list, each place with its group on the scale.
    private var browsed: [GalleryEntry] {
        GalleryArranger.entries(releases, sort: sort, filter: filter)
    }

    private var arranged: [CachedRelease] {
        browsed.map(\.release)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                content
                    .disabled(menu != nil)
                    .onExitCommand(perform: releases.isEmpty ? nil : { toolbarFocus = lastToolbarStop })
                toolbar
                    .opacity(toolbarIsShown ? 1 : 0)
                    .animation(.easeInOut(duration: toolbarFadeTime), value: toolbarIsShown)
            }
            .navigationDestination(item: $selected) { release in
                recordScreen(for: release)
            }
            .overlay(alignment: .bottom) { refreshHUD }
        }
        // Menu on the remote dismisses the cover and returns to the gallery.
        .fullScreenCover(isPresented: $showingSettings) { settingsScreen }
        .task {
            if let stored = preferences.first {
                layout = stored.galleryLayout
                sort = stored.gallerySort
            }
        }
        .onChange(of: layout) { _, new in preferences.first?.galleryLayout = new }
        .onChange(of: sort) { _, new in
            preferences.first?.gallerySort = new
            revealBrowsed()
        }
        .onChange(of: filter) { _, _ in revealBrowsed() }
        .onChange(of: toolbarFocus) { _, new in
            if let new { lastToolbarStop = new.control }
        }
        .onChange(of: selected == nil) { wasNil, isNil in
            // Back from a record: the cover of that record gets focus, not Suggest.
            if !wasNil, isNil {
                reveal = CoverReveal(index: GalleryArranger.index(of: browsedReleaseID, in: arranged), takesFocus: true)
            }
        }
        .onChange(of: showingSettings) { _, showing in
            // Back from Settings: focus returns visibly to the Settings control.
            if !showing { focusSettingsSoon() }
        }
    }

    /// In the Gallery the toolbar fades out while the tide moves. In the Grid
    /// it is on screen only while it has focus or one of its menus is open.
    private var toolbarIsShown: Bool {
        if releases.isEmpty { return true }
        switch layout {
        case .coverFlow: return !tideEngaged
        case .grid: return toolbarFocus != nil || menu != nil
        }
    }

    private var toolbarFadeTime: TimeInterval {
        if layout == .grid { return GridLook.toolbarFade }
        return tideEngaged ? TideTiming.galleryFadeIn : TideTiming.galleryFadeOut
    }

    /// The Grid, with what it shares with the Gallery: the record the
    /// collection is on, the scale's tape and the filter. A repeated record
    /// is shown once, and the tape is cut to match.
    private var gridView: some View {
        var seen: Set<Int> = []
        let entries = browsed.filter { seen.insert($0.release.releaseId).inserted }
        return MosaicGridView(
            releases: entries.map(\.release),
            onOpen: { release in openRecord(release) },
            onMoveUp: { toolbarFocus = lastToolbarStop },
            landingID: browsedReleaseID,
            reveal: reveal,
            onBrowse: { browsedReleaseID = $0 },
            tape: ScaleTape(groups: entries.map(\.group)),
            filterGenre: filter?.genre,
            filterStyle: filter?.style,
            toolbarShown: toolbarIsShown
        )
    }

    /// The one toolbar for both views, floating over the collection.
    private var toolbar: some View {
        GalleryToolbar(
            releases: releases,
            sort: $sort,
            filter: $filter,
            layout: $layout,
            menu: $menu,
            focus: $toolbarFocus,
            suggest: suggest
        ) {
            settingsButton
        }
    }

    /// Opens a random record from the current (sorted/filtered) collection
    /// straight into the track view, and puts the cover under the needle.
    private func suggest() {
        guard let index = arranged.indices.randomElement() else { return }
        // No focus here: the record is on screen, and the cover takes focus
        // when the record is left.
        reveal = CoverReveal(index: index, takesFocus: false)
        openedBySuggest = true
        selected = arranged[index]
    }

    /// The sticker on a suggested record: another random record from the
    /// same list takes its place, never the one on screen.
    private func suggestAnother() {
        let current = selected?.releaseId
        let others = arranged.indices.filter { arranged[$0].releaseId != current }
        guard let index = others.randomElement() else { return }
        reveal = CoverReveal(index: index, takesFocus: false)
        selected = arranged[index]
    }

    /// The record screen for `release`. Kept out of `body`, whose type the
    /// compiler could not work out with this built inline. A suggested record
    /// gets the sticker's action; one opened from the collection gets none.
    /// Another suggestion swaps the record in place, so each record has its
    /// own identity and with it a screen of its own.
    private func recordScreen(for release: CachedRelease) -> some View {
        var another: (() -> Void)?
        if openedBySuggest {
            another = { suggestAnother() }
        }
        return RecordView(release: release, onAnotherSuggestion: another)
            .id(release.releaseId)
    }

    /// Opens a record chosen in the collection.
    private func openRecord(_ release: CachedRelease) {
        openedBySuggest = false
        selected = release
    }

    /// A sort or filter change keeps the record under the needle when it is
    /// still in the list, and otherwise starts at the first one.
    private func revealBrowsed() {
        reveal = CoverReveal(index: GalleryArranger.index(of: browsedReleaseID, in: arranged), takesFocus: false)
    }

    private func focusSettingsSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            toolbarFocus = .settings
        }
    }

    /// The gear at the end of the toolbar. It opens Settings in full screen.
    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 30))
        }
        .buttonStyle(ToolbarButtonStyle(width: ToolbarSize.settings, centered: true))
        .accessibilityLabel("Settings")
        .focused($toolbarFocus, equals: .settings)
    }

    /// Settings, with what it shows of the Gallery: the account, the refresh
    /// and the record last looked at. Kept out of `body`, to keep its type
    /// simple for the compiler.
    private var settingsScreen: some View {
        SettingsView(
            accountName: accountName,
            refreshProgress: refreshProgress,
            refreshMessage: refreshMessage,
            preview: scalePreview,
            startRefresh: { Task { await runRefresh() } },
            signOut: { erase in
                showingSettings = false
                Task { await signOut(erase: erase) }
            }
        )
    }

    private var refreshProgress: SettingsRefreshProgress? {
        if case .running(let processed, let total) = refresh {
            return SettingsRefreshProgress(processed: processed, total: total)
        }
        return nil
    }

    /// How the last refresh ended, in the words of the pill at the bottom of
    /// the Gallery, which Settings covers.
    private var refreshMessage: String? {
        switch refresh {
        case .idle, .running: nil
        case .done(let stored): "Updated \(stored)"
        case .failed(let message): "Refresh failed. \(message)"
        }
    }

    /// The record the Gallery was last on, for the scale's preview.
    private var scalePreview: SettingsScalePreview? {
        let entries = browsed
        guard !entries.isEmpty else { return nil }
        let index = GalleryArranger.index(of: browsedReleaseID, in: entries.map(\.release))
        return SettingsScalePreview(
            title: entries[index].release.title,
            artist: entries[index].release.artistDisplayName,
            tape: ScaleTape(groups: entries.map(\.group)),
            index: index
        )
    }

    private var isRefreshing: Bool {
        if case .running = refresh { return true }
        return false
    }

    private var accountName: String {
        let name = preferences.first?.discogsUsername ?? ""
        return name.isEmpty ? "Discogs" : name
    }

    /// Transient progress pill shown while a manual refresh runs, for when
    /// Settings is left while it does.
    @ViewBuilder
    private var refreshHUD: some View {
        switch refresh {
        case .idle:
            EmptyView()
        case .running(let processed, let total):
            hudPill(total > 0 ? "Refreshing… \(processed)/\(total)" : "Refreshing…", showsSpinner: true)
        case .done(let stored):
            hudPill("Updated \(stored)", showsSpinner: false)
        case .failed(let message):
            hudPill("Refresh failed. \(message)", showsSpinner: false)
        }
    }

    private func hudPill(_ text: String, showsSpinner: Bool) -> some View {
        HStack(spacing: 14) {
            if showsSpinner { ProgressView() }
            Text(text)
                .font(.headline)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .glassBar()
        .padding(.bottom, 60)
        .transition(.opacity)
    }

    private func runRefresh() async {
        withAnimation { refresh = .running(processed: 0, total: 0) }
        let service = CollectionSyncService(modelContainer: modelContext.container)
        do {
            let summary = try await service.sync(using: client, forceFullBuild: true) { update in
                Task { @MainActor in
                    refresh = .running(processed: update.processed, total: update.total)
                }
            }
            withAnimation { refresh = .done(stored: summary.storedReleaseCount) }
            try? await Task.sleep(for: .seconds(2))
            if case .done = refresh { withAnimation { refresh = .idle } }
        } catch {
            // A 401 never lands here for long: the client's hook has already
            // sent the app back to onboarding.
            withAnimation { refresh = .failed(message: error.localizedDescription) }
            // Longer than the success pill, so the reason can be read.
            try? await Task.sleep(for: .seconds(5))
            if case .failed = refresh { withAnimation { refresh = .idle } }
        }
    }

    private func signOut(erase: Bool) async {
        if erase {
            try? modelContext.eraseLibrary()
        }
        await authenticator.signOut()
    }

    @ViewBuilder
    private var content: some View {
        if releases.isEmpty {
            EmptyCollectionView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch layout {
            case .coverFlow:
                // Fills the entire screen; the toolbar floats over the top.
                let entries = browsed
                CoverFlowView(
                    releases: entries.map(\.release),
                    onOpen: { release in openRecord(release) },
                    onMoveUp: { toolbarFocus = lastToolbarStop },
                    reveal: reveal,
                    onBrowse: { browsedReleaseID = $0 },
                    tape: ScaleTape(groups: entries.map(\.group)),
                    tideEngaged: $tideEngaged
                )
            case .grid:
                gridView
            }
        }
    }
}

private extension View {
    /// Wraps the toolbar in tvOS 26 Liquid Glass (a floating glass capsule);
    /// falls back to a frosted material on tvOS 18–25.
    @ViewBuilder
    func glassBar() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

}

private struct EmptyCollectionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.3))
            Text("No vinyl yet")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text("Add vinyl to your Discogs collection, then refresh.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: CachedRelease.self, UserPreferences.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    for index in 1...8 {
        context.insert(CachedRelease(
            releaseId: index,
            instanceId: index * 10,
            title: "Album \(index)",
            artistDisplayName: "Artist \(index)",
            year: 2000 + index,
            dateAdded: .now.addingTimeInterval(Double(-index) * 86_400),
            genres: ["Rock"],
            styles: ["Indie Rock"],
            discogsCoverURL: "",
            thumbURL: ""
        ))
    }
    let credentials = DiscogsCredentials(username: "preview", accessToken: "", accessTokenSecret: "")
    return GalleryView(
        authenticator: DiscogsAuthenticator(),
        client: DiscogsClient(credentials: credentials)
    )
    .modelContainer(container)
}
