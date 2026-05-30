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
    /// Names credited as "Composed By" on this track (from Discogs extraartists).
    let composers: [String]

    enum CodingKeys: String, CodingKey {
        case position, title, duration, extraartists
        case type = "type_"
    }

    private struct Credit: Decodable {
        let name: String
        let role: String

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        }

        enum CodingKeys: String, CodingKey { case name, role }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "track"
        let credits = try c.decodeIfPresent([Credit].self, forKey: .extraartists) ?? []
        composers = credits
            .filter { $0.role.localizedCaseInsensitiveContains("Composed By") }
            .map { cleanArtistName($0.name) }
            .filter { !$0.isEmpty }
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

    /// The vinyl side parsed from the Discogs position. Handles:
    ///   "A1"       → "A"   — single-disc, side letter at the start
    ///   "C1"/"D1"  → "C"/"D" — multi-disc with continuous lettering
    ///   "1-A1"     → "A"   — disc-prefixed (hyphen separator)
    ///   "2-A1"     → "C"   — disc 2 maps onto continuous lettering
    ///   "1.A1"     → "A"   — disc-prefixed (dot separator)
    ///   "1A1"      → "A"   — disc-prefixed (no separator)
    /// For disc-prefixed positions we shift the letter by `(disc - 1) * 2`
    /// so a 2xLP's "1-A" and "2-A" become Side A and Side C — the convention
    /// vinyl box sets use universally. Without this mapping a 2xLP's disc 2
    /// tracks would either collide with disc 1's letters or (when Discogs
    /// uses a leading digit) be parsed as having no side at all and disappear
    /// from the sides list.
    /// nil for headings or positions without any side letter.
    var side: String? {
        guard !isHeading else { return nil }
        let (disc, letters) = splitDiscAndLetters(position)
        guard !letters.isEmpty else { return nil }
        guard letters.count == 1,
              let scalar = letters.unicodeScalars.first,
              ("A"..."Z").contains(letters) else {
            return letters // unusual code (e.g. "AA"); pass through verbatim
        }
        let baseOffset = Int(scalar.value - UnicodeScalar("A").value)
        let totalOffset = max(0, disc - 1) * 2 + baseOffset
        guard totalOffset < 26,
              let mapped = UnicodeScalar(UInt32(totalOffset) + UnicodeScalar("A").value) else {
            return letters
        }
        return String(mapped)
    }
}

/// Splits a Discogs position string into (disc number, side letters).
/// Returns `(disc: 1, letters: "")` for a position with no recognisable side.
/// Examples: "A1" → (1, "A"), "1-A1" → (1, "A"), "2-A1" → (2, "A"),
/// "1.B3" → (1, "B"), "12" → (1, ""), "1" → (1, "").
private func splitDiscAndLetters(_ position: String) -> (disc: Int, letters: String) {
    var idx = position.startIndex
    var digits = ""
    while idx < position.endIndex, position[idx].isNumber {
        digits.append(position[idx])
        idx = position.index(after: idx)
    }
    if idx < position.endIndex, position[idx] == "-" || position[idx] == "." {
        idx = position.index(after: idx)
    }
    var letters = ""
    while idx < position.endIndex, position[idx].isLetter {
        letters.append(position[idx])
        idx = position.index(after: idx)
    }
    // Leading digits with no following letters = a track number, not a disc
    // prefix (e.g. "12" is track 12 on a CD, disc number stays at 1).
    let disc = letters.isEmpty ? 1 : (Int(digits) ?? 1)
    return (disc, letters.uppercased())
}

/// Discogs disambiguates duplicate artist names with a trailing " (2)", " (3)", etc.
private func cleanArtistName(_ name: String) -> String {
    name.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
}
