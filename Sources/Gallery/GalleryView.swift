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
    @FocusState private var toolbarFocused: Bool

    private enum RefreshState: Equatable {
        case idle
        case running(processed: Int, total: Int)
        case done(stored: Int)
        case failed
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
        HStack(spacing: 18) {
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
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .glassBar()
        // Keep left/right focus moves among the controls. Without this the
        // full-screen view behind the bar (CoverFlow's giant button, or any
        // mosaic tile) wins horizontal focus moves and traps the user. Down
        // escapes via the mosaic's focus trampoline / CoverFlow's geometry.
        .focusSection()
        .padding(.top, 28)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.4))
            .frame(width: 2, height: 32)
            .padding(.horizontal, 6)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(GallerySort.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            SwiftUI.Label("Sort: \(sort.displayName)", systemImage: "arrow.up.arrow.down")
        }
        .focused($toolbarFocused) // target for swipe-up from the CoverFlow
    }

    @ViewBuilder
    private var genreMenu: some View {
        let tags = GalleryArranger.filterTags(releases)
        if !tags.isEmpty {
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
        Menu {
            Button {
                Task { await runRefresh() }
            } label: {
                SwiftUI.Label("Refresh collection", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            Section {
                Text("Account: \(accountName)")
                Button {
                    Task { await signOut(erase: false) }
                } label: {
                    SwiftUI.Label("Sign out (keep library)", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive) {
                    Task { await signOut(erase: true) }
                } label: {
                    SwiftUI.Label("Sign out & erase library", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
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
        case .failed:
            hudPill("Refresh failed", showsSpinner: false)
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
            withAnimation { refresh = .failed }
            try? await Task.sleep(for: .seconds(2))
            if case .failed = refresh { withAnimation { refresh = .idle } }
        }
    }

    private func signOut(erase: Bool) async {
        if erase {
            try? modelContext.delete(model: CachedRelease.self)
            if let prefs = preferences.first {
                prefs.lastSyncDate = nil
                prefs.discogsUsername = ""
            }
            try? modelContext.save()
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
