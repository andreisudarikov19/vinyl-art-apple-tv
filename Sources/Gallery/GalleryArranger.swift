import Foundation

extension GallerySort {
    var displayName: String {
        switch self {
        case .recentlyAdded: return "Recently added"
        case .artist: return "Artist"
        case .album: return "Album"
        case .year: return "Year"
        case .genre: return "Genre"
        }
    }
}

/// What the gallery shows: a broad genre, or a style within that genre.
/// A style is never a sort; it only narrows the list.
struct GalleryFilter: Equatable {
    var genre: String
    var style: String?

    func matches(_ release: CachedRelease) -> Bool {
        guard release.genres.contains(genre) else { return false }
        guard let style else { return true }
        return release.styles.contains(style)
    }
}

/// One row of the genre menu: a genre in the collection, how many records
/// carry it, and the styles found on those records.
struct GenreOption: Identifiable, Equatable {
    let name: String
    let count: Int
    let styles: [StyleOption]
    var id: String { name }
}

/// One row of a genre's style column: a style found on records of that
/// genre, and how many of those records carry it.
struct StyleOption: Identifiable, Equatable {
    let name: String
    let count: Int
    var id: String { name }
}

/// Pure sort/filter logic for the gallery, kept separate from the view so it
/// can be unit-tested without SwiftData or UI.
enum GalleryArranger {
    /// The genre menu's rows: the genres the collection contains, A to Z,
    /// each with its styles. Discogs does not tie a style to a genre, so a
    /// genre's styles are the styles found on its records.
    static func genreOptions(_ releases: [CachedRelease]) -> [GenreOption] {
        var counts: [String: Int] = [:]
        var styleCounts: [String: [String: Int]] = [:]
        for release in releases {
            for genre in Set(release.genres) where !genre.isEmpty {
                counts[genre, default: 0] += 1
                for style in Set(release.styles) where !style.isEmpty {
                    styleCounts[genre, default: [:]][style, default: 0] += 1
                }
            }
        }
        return counts.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { genre in
                let styles = (styleCounts[genre] ?? [:])
                    .map { StyleOption(name: $0.key, count: $0.value) }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return GenreOption(name: genre, count: counts[genre] ?? 0, styles: styles)
            }
    }

    static func arrange(
        _ releases: [CachedRelease],
        sort: GallerySort,
        filter: GalleryFilter?
    ) -> [CachedRelease] {
        let filtered: [CachedRelease]
        if let filter {
            filtered = releases.filter(filter.matches)
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
        case .genre:
            return byGenre(filtered, only: filter?.genre)
        }
    }

    /// Genre sort: genres A to Z, records by artist then album inside each.
    /// A record with several genres appears under each of them. With a genre
    /// filter on, only that genre's group is listed. Records with no genre
    /// come last.
    private static func byGenre(_ releases: [CachedRelease], only genre: String?) -> [CachedRelease] {
        var entries: [(genre: String, release: CachedRelease)] = []
        for release in releases {
            let groups: [String]
            if let genre {
                groups = [genre]
            } else if release.genres.isEmpty {
                groups = [""]
            } else {
                groups = Array(Set(release.genres))
            }
            entries += groups.map { (genre: $0, release: release) }
        }
        return entries.sorted { lhs, rhs in
            if lhs.genre != rhs.genre {
                if lhs.genre.isEmpty != rhs.genre.isEmpty { return rhs.genre.isEmpty }
                return lhs.genre.localizedStandardCompare(rhs.genre) == .orderedAscending
            }
            return ordered(
                lhs.release.artistDisplayName, rhs.release.artistDisplayName,
                then: lhs.release.title, rhs.release.title
            )
        }
        .map(\.release)
    }

    /// The releases with each one kept once, at its first place. The grid
    /// identifies its tiles by record, so it shows a repeated record once.
    static func uniqued(_ releases: [CachedRelease]) -> [CachedRelease] {
        var seen: Set<Int> = []
        return releases.filter { seen.insert($0.releaseId).inserted }
    }

    /// Where a record sits in a list, or the first place when it is absent.
    /// Keeps the record under the needle across a sort or filter change.
    static func index(of releaseID: Int?, in releases: [CachedRelease]) -> Int {
        guard let releaseID else { return 0 }
        return releases.firstIndex { $0.releaseId == releaseID } ?? 0
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
