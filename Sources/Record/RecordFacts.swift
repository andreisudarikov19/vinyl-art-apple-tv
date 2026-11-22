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
}
