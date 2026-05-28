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
    @State private var selected: CachedRelease?
    @State private var showingSettings = false

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
            .fullScreenCover(isPresented: $showingSettings) {
                SettingsView(authenticator: authenticator, client: client)
            }
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
                sortMenu
                genreMenu
                layoutToggle
            }
            settingsButton
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .glassBar()
        .padding(.top, 28)
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
    }

    @ViewBuilder
    private var genreMenu: some View {
        let tags = GalleryArranger.filterTags(releases)
        if !tags.isEmpty {
            Menu {
                Picker("Genre", selection: $tag) {
                    Text("All Genres").tag(String?.none)
                    ForEach(tags, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
            } label: {
                SwiftUI.Label(tag ?? "All Genres", systemImage: "line.3.horizontal.decrease.circle")
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

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
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
                CoverFlowView(releases: arranged) { selected = $0 }
                    .id("\(sort.rawValue)-\(tag ?? "all")")
            case .grid:
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280), spacing: 50)],
                        spacing: 56
                    ) {
                        ForEach(arranged) { release in
                            GalleryTile(release: release) { selected = release }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 150) // clear the floating toolbar
                    .padding(.bottom, 60)
                }
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

private struct GalleryTile: View {
    let release: CachedRelease
    var size: CGFloat = 280
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) { cover }
                .buttonStyle(.card)
            Text(release.artistDisplayName)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(release.title)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(release.artistDisplayName) – \(release.title)")
    }

    private var cover: some View {
        LazyImage(url: release.preferredCoverURL) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.white.opacity(0.08))
                    Image(systemName: "opticaldisc")
                        .font(.system(size: size / 4))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
