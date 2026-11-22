import Foundation

/// The text of the facts table on the record screen.
enum RecordFacts {
    /// "42 tracks · 1 h 52 min". The time is left out when any track lacks a
    /// duration, so a partial total is never shown. Nil for no tracks.
    static func length(durations: [String]) -> String? {
        guard !durations.isEmpty else { return nil }
        let tracks = durations.count == 1 ? "1 track" : "\(durations.count) tracks"
        guard let seconds = totalSeconds(durations) else { return tracks }
        return "\(tracks) · \(playingTime(seconds: seconds))"
    }

    /// "37 min", "1 h 52 min", "2 h". Rounded to the nearest minute, never
    /// below one.
    static func playingTime(seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// The sum of Discogs durations ("m:ss" or "h:mm:ss"), or nil if any of
    /// them doesn't parse or they add up to nothing.
    static func totalSeconds(_ durations: [String]) -> Int? {
        var total = 0
        for duration in durations {
            let parts = duration.split(separator: ":").map { Int($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            let numbers = parts.compactMap { $0 }
            switch numbers.count {
            case 2: total += numbers[0] * 60 + numbers[1]
            case 3: total += numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
            default: return nil
            }
        }
        return total > 0 ? total : nil
    }

    /// "1976 · Netherlands", "1976", "Netherlands", or nil when neither is
    /// known. Discogs gives 0 for an unknown year; the country is shown as
    /// Discogs spells it.
    static func published(year: Int, country: String?) -> String? {
        let place = country?.trimmingCharacters(in: .whitespaces)
        let hasPlace = !(place ?? "").isEmpty
        switch (year > 0, hasPlace) {
        case (true, true): return "\(year) · \(place ?? "")"
        case (true, false): return String(year)
        case (false, true): return place
        case (false, false): return nil
        }
    }

    // MARK: - The table

    /// The rows of the facts table, in order. A row with nothing to say is
    /// left out, so a record with no label or no styles has a shorter table.
    /// - Parameters:
    ///   - country: Known once the release has loaded; the PUBLISHED row shows
    ///     the year alone until then.
    ///   - durations: Every track of every side, empty until the release has
    ///     loaded, when the LENGTH row appears.
    ///   - titleTakesTwoLines: The album title is long. The genre and style
    ///     rows are then held to one line, so the table clears the Discogs line.
    static func rows(
        year: Int,
        country: String?,
        genres: [String],
        styles: [String],
        label: String?,
        durations: [String],
        titleTakesTwoLines: Bool
    ) -> [RecordFactRow] {
        var rows: [RecordFactRow] = []
        let lines = titleTakesTwoLines ? 1 : 2
        if let text = Self.published(year: year, country: country) {
            rows.append(RecordFactRow(label: "PUBLISHED", value: text))
        }
        if !genres.isEmpty {
            rows.append(RecordFactRow(label: "GENRE", value: genres.joined(separator: ", "), lineLimit: lines))
        }
        if !styles.isEmpty {
            rows.append(RecordFactRow(label: "STYLE", value: styles.joined(separator: ", "), isQuiet: true, lineLimit: lines))
        }
        if let name = label?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            rows.append(RecordFactRow(label: "LABEL", value: name))
        }
        if let whole = Self.length(durations: durations) {
            // "42 tracks" leads; " · 1 h 52 min" follows, quieter.
            if let split = whole.range(of: " · ") {
                rows.append(RecordFactRow(
                    label: "LENGTH",
                    value: String(whole[..<split.lowerBound]),
                    tail: String(whole[split.lowerBound...])
                ))
            } else {
                rows.append(RecordFactRow(label: "LENGTH", value: whole))
            }
        }
        return rows
    }

    /// Whether an album title runs to a second line in the left column
    /// (Fraunces 52 in 560 pt). A count of characters, not a measurement:
    /// about 21 fit on a line.
    static func titleTakesTwoLines(_ title: String) -> Bool {
        title.count > 21
    }
}

/// One row of the record screen's facts table.
struct RecordFactRow: Identifiable, Equatable, Sendable {
    /// "PUBLISHED", "GENRE", "STYLE", "LABEL" or "LENGTH".
    let label: String
    let value: String
    /// A quieter end to the value: " · 1 h 52 min".
    var tail = ""
    /// The whole value is second-rank: the styles.
    var isQuiet = false
    var lineLimit = 1

    var id: String { label }
}
