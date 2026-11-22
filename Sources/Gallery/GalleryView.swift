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
    @State private var refresh: RefreshState = .idle
    @State private var showingAbout = false
    @FocusState private var toolbarFocus: ToolbarFocus?

    private enum RefreshState: Equatable {
        case idle
        case running(processed: Int, total: Int)
        case done(stored: Int)
        case failed(message: String)
    }

    private var arranged: [CachedRelease] {
        GalleryArranger.arrange(releases, sort: sort, filter: filter)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                content
                    .disabled(menu != nil)
                    .onExitCommand(perform: releases.isEmpty ? nil : { toolbarFocus = lastToolbarStop })
                toolbar
            }
            .navigationDestination(item: $selected) { release in
                RecordView(release: release)
            }
            .overlay(alignment: .bottom) { refreshHUD }
        }
        // Menu on the remote dismisses the cover and returns to the gallery.
        .fullScreenCover(isPresented: $showingAbout) { AboutView() }
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
        .onChange(of: showingAbout) { _, showing in
            // Back from About: focus returns visibly to the Settings control.
            if !showing { focusSettingsSoon() }
        }
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
            settingsMenu
        }
    }

    /// Opens a random record from the current (sorted/filtered) collection
    /// straight into the track view, and puts the cover under the needle.
    private func suggest() {
        guard let index = arranged.indices.randomElement() else { return }
        // No focus here: the record is on screen, and the cover takes focus
        // when the record is left.
        reveal = CoverReveal(index: index, takesFocus: false)
        selected = arranged[index]
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

    private var settingsMenu: some View {
        SettingsMenu(
            accountName: accountName,
            isRefreshing: isRefreshing,
            haloAutoEngage: preferences.first?.haloAutoEngage ?? true,
            // Creates the preferences row if it's missing.
            setHaloAutoEngage: { UserPreferences.current(in: modelContext).haloAutoEngage = $0 },
            refresh: { Task { await runRefresh() } },
            signOut: { erase in Task { await signOut(erase: erase) } },
            showAbout: { showingAbout = true }
        )
        .equatable()
        .focused($toolbarFocus, equals: .settings)
    }

    private var isRefreshing: Bool {
        if case .running = refresh { return true }
        return false
    }

    private var accountName: String {
        let name = preferences.first?.discogsUsername ?? ""
        return name.isEmpty ? "Discogs" : name
    }

    /// Transient progress pill shown while a manual refresh runs (the menu
    /// closes on tap, so feedback surfaces here instead of a sheet).
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
                CoverFlowView(
                    releases: arranged,
                    onOpen: { selected = $0 },
                    onMoveUp: { toolbarFocus = lastToolbarStop },
                    reveal: reveal,
                    onBrowse: { browsedReleaseID = $0 }
                )
            case .grid:
                MosaicGridView(
                    releases: GalleryArranger.uniqued(arranged),
                    onOpen: { selected = $0 },
                    onMoveUp: { toolbarFocus = lastToolbarStop }
                )
            }
        }
    }
}

/// Equal when what it shows is equal. Its actions are new closures on every
/// gallery update, so SwiftUI would always see it as changed, but they do
/// the same thing each time. The halo setting comes in as a value: reading
/// the preferences row here would update the menu on every save as well.
private struct SettingsMenu: View, Equatable {
    let accountName: String
    let isRefreshing: Bool
    let haloAutoEngage: Bool
    let setHaloAutoEngage: @MainActor @Sendable (Bool) -> Void
    let refresh: () -> Void
    let signOut: (_ erase: Bool) -> Void
    let showAbout: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountName == rhs.accountName
            && lhs.isRefreshing == rhs.isRefreshing
            && lhs.haloAutoEngage == rhs.haloAutoEngage
    }

    var body: some View {
        Menu {
            Button(action: refresh) {
                SwiftUI.Label("Refresh collection", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            // Plain text: tvOS draws a tick beside it when it's on.
            Toggle("Engage halo automatically", isOn: Binding(get: { haloAutoEngage }, set: { setHaloAutoEngage($0) }))
            Section {
                Text("Account: \(accountName)")
                Button {
                    signOut(false)
                } label: {
                    SwiftUI.Label("Sign out (keep library)", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    signOut(true)
                } label: {
                    SwiftUI.Label("Sign out & erase library", systemImage: "trash")
                }
            }
            // Like the account line: plain text, so it reads as information.
            Section {
                Text(AppVersion.current)
                Button(action: showAbout) {
                    SwiftUI.Label("About", systemImage: "info.circle")
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 30))
        }
        .buttonStyle(ToolbarButtonStyle(width: ToolbarSize.settings, centered: true))
        .accessibilityLabel("Settings")
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
