import Foundation

/// One credit line below a track title — a role prefix ("Composed by",
/// "Vocals by", "Backing vocals by", etc.) plus the names of everyone who
/// holds that role on the track. Multiple credit types can coexist (a song
/// can be `Composed by` X and `Vocals by` Y simultaneously); each renders
/// as its own line in the same subdued style.
struct TrackCredit: Equatable, Sendable, Hashable {
    /// Sentence-case display prefix (e.g. "Composed by", "Backing vocals by").
    let role: String
    /// Names credited under this role, in the order they appear on Discogs.
    let names: [String]

    /// Full display string, e.g. "Backing vocals by Alice, Bob".
    var displayLine: String {
        names.isEmpty ? role : "\(role) \(names.joined(separator: ", "))"
    }
}

struct RecordTrack: Identifiable, Equatable, Sendable {
    let id: String
    let position: String
    let title: String
    /// Tracklist-displayable credits in the order their roles first appear
    /// in the Discogs extraartists list. Producer / engineer / instrument
    /// credits are filtered out upstream — too much detail per row.
    let credits: [TrackCredit]
    let duration: String
}

/// Maps a Discogs `extraartists` role string to a sentence-case display
/// prefix for the tracklist. Returns nil for roles we don't surface (mixing,
/// engineering, instrument credits) — those are interesting but too noisy
/// to render on every row.
///
/// Examples:
///   "Composed By"      -> "Composed by"
///   "Written-By"       -> "Written by"
///   "Lyrics By"        -> "Lyrics by"
///   "Music By"         -> "Music by"
///   "Arranged By"      -> "Arranged by"
///   "Vocals"           -> "Vocals by"
///   "Lead Vocals"      -> "Lead vocals by"
///   "Backing Vocals"   -> "Backing vocals by"
///   "Vocals [Backing]" -> "Backing vocals by"
///   "Co-lead Vocals"   -> "Co-lead vocals by"
///   "Featuring"        -> "Featuring"
///   "Producer"         -> nil (skipped)
func tracklistRoleDisplay(_ role: String) -> String? {
    let lower = role.lowercased()
    if lower.contains("composed") { return "Composed by" }
    if lower.contains("written") || lower.contains("words") { return "Written by" }
    if lower.contains("lyrics") { return "Lyrics by" }
    // "Music by" should match but not "Musicians" / "Mastered" / etc.
    if lower.contains("music") && !lower.contains("musician") && !lower.contains("mastered") {
        return "Music by"
    }
    if lower.contains("arranged") { return "Arranged by" }
    // Vocal credits — order matters: most-specific first, since a generic
    // "Vocals" with a Discogs `[Backing]` qualifier must still resolve to
    // the backing prefix.
    if lower.contains("backing") && lower.contains("vocals") { return "Backing vocals by" }
    if lower.contains("co-lead") && lower.contains("vocals") { return "Co-lead vocals by" }
    if lower.contains("lead") && lower.contains("vocals") { return "Lead vocals by" }
    if lower.contains("vocals") { return "Vocals by" }
    if lower.contains("featuring") || lower.hasPrefix("feat") { return "Featuring" }
    return nil
}

struct RecordSide: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let tracks: [RecordTrack]
}

/// Groups a Discogs tracklist into vinyl sides (A, B, C, …) in order of
/// appearance. Headings are dropped; releases without side letters collapse
/// into a single "Tracklist" side.
enum RecordSides {
    static func from(_ tracklist: [TrackEntry]) -> [RecordSide] {
        var order: [String] = []
        var grouped: [String: [RecordTrack]] = [:]
        var ordinal = 0

        for entry in tracklist where !entry.isHeading {
            ordinal += 1
            let key = entry.side ?? noSideKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(
                RecordTrack(
                    id: "\(ordinal)",
                    position: entry.position,
                    title: entry.title,
                    credits: entry.credits,
                    duration: entry.duration
                )
            )
        }

        return order.map { key in
            RecordSide(id: key, name: name(for: key), tracks: grouped[key] ?? [])
        }
    }

    private static let noSideKey = "—"

    private static func name(for key: String) -> String {
        key == noSideKey ? "Tracklist" : "Side \(key)"
    }
}
