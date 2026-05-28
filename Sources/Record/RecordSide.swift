import Foundation

struct RecordTrack: Identifiable, Equatable, Sendable {
    let id: String
    let position: String
    let title: String
    let duration: String
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
