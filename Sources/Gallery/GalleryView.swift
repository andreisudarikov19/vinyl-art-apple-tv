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
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if releases.isEmpty {
                        Spacer()
                        EmptyCollectionView()
                        Spacer()
                    } else {
                        filterRow
                        collection
                    }
                }
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your Collection")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            if !releases.isEmpty {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(GallerySort.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    SwiftUI.Label("Sort: \(sort.displayName)", systemImage: "arrow.up.arrow.down")
                }
                Button {
                    layout = layout == .grid ? .coverFlow : .grid
                } label: {
                    Image(systemName: layout == .grid ? "square.stack" : "square.grid.2x2")
                }
                .accessibilityLabel(layout == .grid ? "Switch to CoverFlow" : "Switch to grid")
            }
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var filterRow: some View {
        let tags = GalleryArranger.filterTags(releases)
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    chip(title: "All", isSelected: tag == nil) { tag = nil }
                    ForEach(tags, id: \.self) { name in
                        chip(title: name, isSelected: tag == name) { tag = name }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 24)
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.bordered)
            .tint(isSelected ? .white : .secondary)
    }

    @ViewBuilder
    private var collection: some View {
        switch layout {
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
                .padding(60)
            }
        case .coverFlow:
            CoverFlowView(releases: arranged) { selected = $0 }
                .id("\(sort.rawValue)-\(tag ?? "all")")
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
