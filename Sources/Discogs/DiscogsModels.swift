import Foundation

struct DiscogsCollectionPage: Decodable, Sendable {
    let pagination: Pagination
    let releases: [CollectionRelease]

    struct Pagination: Decodable, Sendable {
        let page: Int
        let pages: Int
        let perPage: Int
        let items: Int

        enum CodingKeys: String, CodingKey {
            case page, pages, items
            case perPage = "per_page"
        }
    }
}

struct CollectionRelease: Decodable, Sendable, Identifiable {
    let id: Int
    let instanceId: Int
    let dateAdded: String
    let basicInformation: BasicInformation

    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case dateAdded = "date_added"
        case basicInformation = "basic_information"
    }
}

struct BasicInformation: Decodable, Sendable {
    let id: Int
    let masterId: Int?
    let title: String
    let year: Int
    let thumb: String
    let coverImage: String
    let artists: [Artist]
    let labels: [Label]
    let formats: [Format]
    let genres: [String]
    let styles: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, year, thumb, artists, labels, formats, genres, styles
        case masterId = "master_id"
        case coverImage = "cover_image"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        masterId = try c.decodeIfPresent(Int.self, forKey: .masterId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb) ?? ""
        coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage) ?? ""
        artists = try c.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        formats = try c.decodeIfPresent([Format].self, forKey: .formats) ?? []
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        styles = try c.decodeIfPresent([String].self, forKey: .styles) ?? []
    }
}

struct Artist: Decodable, Sendable {
    let name: String
    let id: Int?
    let join: String?
}

struct Label: Decodable, Sendable {
    let name: String
    let catno: String?
}

struct Format: Decodable, Sendable {
    let name: String
    let qty: String?
    let descriptions: [String]?
}

struct ReleaseDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let tracklist: [TrackEntry]

    enum CodingKeys: String, CodingKey {
        case id, title, tracklist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        tracklist = try c.decodeIfPresent([TrackEntry].self, forKey: .tracklist) ?? []
    }
}

struct TrackEntry: Decodable, Sendable {
    let position: String
    let title: String
    let duration: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case position, title, duration
        case type = "type_"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "track"
    }
}

// MARK: - Derived helpers

extension BasicInformation {
    var isVinyl: Bool {
        formats.contains { $0.name.caseInsensitiveCompare("Vinyl") == .orderedSame }
    }

    var artistDisplayName: String {
        let names = artists.map { cleanArtistName($0.name) }.filter { !$0.isEmpty }
        return names.isEmpty ? "Unknown Artist" : names.joined(separator: ", ")
    }

    var primaryLabel: Label? { labels.first }
}

extension TrackEntry {
    var isHeading: Bool { type == "heading" }

    /// The vinyl side parsed from the position (e.g. "A1" -> "A", "B2" -> "B").
    /// nil for headings or numeric-only positions.
    var side: String? {
        guard !isHeading else { return nil }
        let letters = position.prefix { $0.isLetter }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}

/// Discogs disambiguates duplicate artist names with a trailing " (2)", " (3)", etc.
private func cleanArtistName(_ name: String) -> String {
    name.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
}
