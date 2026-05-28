import Foundation

extension GallerySort {
    var displayName: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .artist: return "Artist"
        case .album: return "Album"
        case .year: return "Year"
        }
    }
}

/// Pure sort/filter logic for the gallery, kept separate from the view so it
/// can be unit-tested without SwiftData or UI.
enum GalleryArranger {
    /// All distinct genres and styles across the collection, sorted for the
    /// filter row. Genres and styles are merged into one "tag" list per the
    /// v1 genre/style-only filter.
    static func filterTags(_ releases: [CachedRelease]) -> [String] {
        var tags: Set<String> = []
        for release in releases {
            tags.formUnion(release.genres)
            tags.formUnion(release.styles)
        }
        return tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func arrange(
        _ releases: [CachedRelease],
        sort: GallerySort,
        tag: String?
    ) -> [CachedRelease] {
        let filtered: [CachedRelease]
        if let tag {
            filtered = releases.filter { $0.genres.contains(tag) || $0.styles.contains(tag) }
        } else {
            filtered = releases
        }

        switch sort {
        case .recentlyAdded:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .artist:
            return filtered.sorted { ordered($0.artistDisplayName, $1.artistDisplayName, then: $0.title, $1.title) }
        case .album:
            return filtered.sorted { ordered($0.title, $1.title, then: $0.artistDisplayName, $1.artistDisplayName) }
        case .year:
            return filtered.sorted {
                if $0.year != $1.year { return $0.year < $1.year }
                return $0.artistDisplayName.localizedStandardCompare($1.artistDisplayName) == .orderedAscending
            }
        }
    }

    /// Locale-aware comparison of `lhs`/`rhs`, falling back to the secondary
    /// keys on a tie.
    private static func ordered(_ lhs: String, _ rhs: String, then lhs2: String, _ rhs2: String) -> Bool {
        switch lhs.localizedStandardCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs2.localizedStandardCompare(rhs2) == .orderedAscending
        }
    }
}
