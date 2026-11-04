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
    /// The movements of a suite or medley, which Discogs lists as an index
    /// entry's sub-tracks. Empty for a plain track.
    let parts: [Part]

    /// One movement of a suite. Discogs' credits on parts are dropped; the
    /// row shows the index's own.
    struct Part: Equatable, Sendable {
        let title: String
        let duration: String
    }
}

/// Discogs durations, written "m:ss" or "h:mm:ss".
enum TrackDuration {
    /// The sum of `durations` as "m:ss", or nil if any of them doesn't parse
    /// (so a partial total is never shown) or they add up to nothing.
    static func total(of durations: [String]) -> String? {
        var total = 0
        for duration in durations {
            guard let secs = seconds(from: duration) else { return nil }
            total += secs
        }
        guard total > 0 else { return nil }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func seconds(from duration: String) -> Int? {
        let parts = duration.split(separator: ":")
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            nums.append(value)
        }
        switch nums.count {
        case 2: return nums[0] * 60 + nums[1]
        case 3: return nums[0] * 3600 + nums[1] * 60 + nums[2]
        default: return nil
        }
    }
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
/// into a single "Tracklist" side. An index entry, a suite or medley, is one
/// row with its parts beneath it.
enum RecordSides {
    static func from(_ tracklist: [TrackEntry]) -> [RecordSide] {
        var rows: [(side: String?, track: RecordTrack)] = []
        for entry in tracklist where !entry.isHeading {
            let runs = sideRuns(of: entry)
            for run in runs {
                rows.append((run.side, track(for: entry, id: rows.count + 1, parts: run.parts, isWhole: runs.count == 1)))
            }
        }

        var order: [String] = []
        var grouped: [String: [RecordTrack]] = [:]
        for row in rows {
            let key = row.side ?? noSideKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row.track)
        }

        return order.map { key in
            RecordSide(id: key, name: name(for: key), tracks: grouped[key] ?? [])
        }
    }

    /// The sides an entry's rows go on, each with the sub-tracks it shows
    /// there; nil where the position names no side. A plain track, or an
    /// index with its own side, is one row on that side. Its parts'
    /// positions aren't read, since Discogs may letter them just "a", "b",
    /// which would read as Sides A and B. An index without a side takes its
    /// parts' sides, with a row on each side they cover.
    private static func sideRuns(of entry: TrackEntry) -> [(side: String?, parts: [TrackEntry])] {
        guard entry.isIndex, entry.side == nil, !entry.subTracks.isEmpty else {
            return [(entry.side, entry.subTracks)]
        }
        var runs: [(side: String?, parts: [TrackEntry])] = []
        for (part, side) in zip(entry.subTracks, fillingGaps(entry.subTracks.map(\.side))) {
            if let last = runs.last, last.side == side {
                runs[runs.count - 1].parts.append(part)
            } else {
                runs.append((side, [part]))
            }
        }
        return runs
    }

    /// The row for `entry`, with `parts` beneath it. A row with all of an
    /// index's parts takes the index's duration when Discogs gives one.
    /// Otherwise, and on each side of an index split across two, since the
    /// index's duration covers both, it's the sum of the row's parts.
    private static func track(for entry: TrackEntry, id: Int, parts: [TrackEntry], isWhole: Bool) -> RecordTrack {
        let duration = isWhole && !entry.duration.isEmpty
            ? entry.duration
            : TrackDuration.total(of: parts.map(\.duration)) ?? ""
        return RecordTrack(
            id: "\(id)",
            position: entry.position,
            title: entry.title,
            credits: entry.credits,
            duration: duration,
            parts: parts.map { RecordTrack.Part(title: $0.title, duration: $0.duration) }
        )
    }

    /// Gives each nil side the nearest side before it, or the first side
    /// when none comes before. All stay nil when there's no side at all.
    private static func fillingGaps(_ sides: [String?]) -> [String?] {
        var current = sides.lazy.compactMap { $0 }.first
        return sides.map { side in
            if let side { current = side }
            return current
        }
    }

    private static let noSideKey = "—"

    private static func name(for key: String) -> String {
        key == noSideKey ? "Tracklist" : "Side \(key)"
    }
}
