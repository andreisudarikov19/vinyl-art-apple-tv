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
    @State private var tag: String?
    @Environment(\.modelContext) private var modelContext
    @State private var selected: CachedRelease?
    @State private var refresh: RefreshState = .idle
    @State private var showingAbout = false
    @FocusState private var toolbarFocused: Bool

    private enum RefreshState: Equatable {
        case idle
        case running(processed: Int, total: Int)
        case done(stored: Int)
        case failed(message: String)
    }

    private var arranged: [CachedRelease] {
        GalleryArranger.arrange(releases, sort: sort, tag: tag)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                content
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
        .onChange(of: sort) { _, new in preferences.first?.gallerySort = new }
    }

    /// One consistent control panel pinned to the top, floating over the
    /// (full-screen) collection. No title — the covers are the content.
    private var toolbar: some View {
        HStack(spacing: 7) {
            if !releases.isEmpty {
                suggestButton
                separator
                sortMenu
                genreMenu
                separator
                layoutToggle
            }
            settingsMenu
        }
        // Match the inner inset on every side (top/bottom/left/right) and use
        // the same 7pt as the HStack spacing so the gaps between controls,
        // around separators, and inside the capsule all read uniform.
        .padding(7)
        .glassBar()
        // Keep left/right focus moves among the controls. Without this the
        // full-screen view behind the bar (CoverFlow's giant button, or any
        // mosaic tile) wins horizontal focus moves and traps the user. Down
        // escapes via the mosaic's focus trampoline / CoverFlow's geometry.
        .focusSection()
        // Sits high in the safe area to match Music's top bar on tvOS — the
        // bar reads "floating chrome" instead of "second header."
        .padding(.top, 12)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.4))
            .frame(width: 2, height: 32)
        // No horizontal padding — the HStack's own spacing (7) provides the
        // gap on either side so it matches the rest of the bar's geometry.
    }

    private var sortMenu: some View {
        SortMenu(sort: $sort)
            .focused($toolbarFocused) // target for swipe-up from the CoverFlow
    }

    @ViewBuilder
    private var genreMenu: some View {
        let tags = GalleryArranger.filterTags(releases)
        if !tags.isEmpty {
            GenreMenu(tags: tags, tag: $tag)
        }
    }

    private var layoutToggle: some View {
        Button {
            layout = layout == .grid ? .coverFlow : .grid
        } label: {
            Image(systemName: layout == .grid ? "square.stack" : "square.grid.2x2")
        }
        .accessibilityLabel(layout == .grid ? "Switch to CoverFlow" : "Switch to grid")
    }

    /// Opens a random album from the current (sorted/filtered) collection
    /// straight into the track view.
    private var suggestButton: some View {
        Button {
            selected = arranged.randomElement()
        } label: {
            SwiftUI.Label("Suggest", systemImage: "sparkles")
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
                    onMoveUp: { toolbarFocused = true }
                )
                .id("\(sort.rawValue)-\(tag ?? "all")")
            case .grid:
                MosaicGridView(
                    releases: arranged,
                    onOpen: { selected = $0 },
                    onMoveUp: { toolbarFocused = true }
                )
            }
        }
    }
}

// MARK: - Toolbar menus

// The menus are views of their own so they update only when what they show
// changes. The gallery's body runs again on every save the cover sweep
// makes, and rebuilding an open menu's content makes tvOS reload it: the
// menu blanks for a moment and comes back.

private struct SortMenu: View {
    @Binding var sort: GallerySort

    var body: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(GallerySort.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            SwiftUI.Label("Sort: \(sort.displayName)", systemImage: "arrow.up.arrow.down")
        }
    }
}

private struct GenreMenu: View {
    let tags: [String]
    @Binding var tag: String?

    var body: some View {
        Menu {
            Picker("Genre", selection: $tag) {
                Text("All genres").tag(String?.none)
                ForEach(tags, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
        } label: {
            SwiftUI.Label(tag ?? "All genres", systemImage: "line.3.horizontal.decrease.circle")
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
    let setHaloAutoEngage: (Bool) -> Void
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
            Toggle("Engage halo automatically", isOn: Binding(get: { haloAutoEngage }, set: setHaloAutoEngage))
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
        }
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
