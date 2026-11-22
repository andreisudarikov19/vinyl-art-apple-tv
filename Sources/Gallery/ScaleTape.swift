import Foundation

/// The model behind the scale under the cover in the Gallery: one tick per
/// entry of the list being browsed, with a taller tick and a label where a
/// group begins. Every scale style draws from this; the styles are looks,
/// not behaviours. See design-handoff/specs/01-gallery-and-scale.md.
struct ScaleTape: Equatable, Sendable {
    /// The group of each entry, in list order: a year, a letter, a genre.
    let groups: [String]

    /// Points between neighbouring ticks.
    static let pitch = 16.0
    /// A label is skipped if it would start within this distance of the one before it.
    static let minimumLabelGap = 96.0
    /// Labels are DM Mono Regular 25 pt and the reading DM Mono Medium 36 pt.
    static let labelSize = 25.0
    static let readingSize = 36.0
    /// Room kept between a label and the one after it, or the reading.
    static let textGap = 16.0

    /// The width of a DM Mono line: 0.6 em a character.
    static func textWidth(_ text: String, size: Double) -> Double {
        Double(text.count) * 0.6 * size
    }

    struct Label: Equatable, Sendable {
        var text: String
        /// Index of the first entry of the group.
        var index: Int
        /// Points from the needle; negative is left.
        var offset: Double
    }

    /// The reading at the needle: the group the current entry belongs to.
    func reading(at current: Int) -> String? {
        groups.indices.contains(current) ? groups[current] : nil
    }

    /// Index of the first entry of every group.
    var groupStarts: [Int] {
        groups.indices.filter { $0 == 0 || groups[$0] != groups[$0 - 1] }
    }

    /// Group starts that carry a label. Decided over the whole tape, not
    /// over what is on screen, so a label never appears or vanishes as the
    /// tape scrolls. A label is 96 pt or more from the one before it, and
    /// further still when that one is wider than 96 pt, so long genre names
    /// do not run into the next.
    var labelledStarts: [Int] {
        var kept: [Int] = []
        for start in groupStarts {
            if let last = kept.last {
                let width = Self.textWidth(groups[last], size: Self.labelSize) + Self.textGap
                let needed = max(Self.minimumLabelGap, width)
                if Double(start - last) * Self.pitch < needed { continue }
            }
            kept.append(start)
        }
        return kept
    }

    /// Whether the tick at `index` is a group tick (24 pt) or a record tick (12 pt).
    func isGroupStart(_ index: Int) -> Bool {
        index == 0 || (groups.indices.contains(index) && groups[index] != groups[index - 1])
    }

    /// Where the tick of entry `index` sits when `current` is under the needle.
    /// `current` is fractional while the tape glides between two entries.
    static func offset(of index: Int, current: Double) -> Double {
        (Double(index) - current) * pitch
    }

    /// The labels to draw when `current` is under the needle.
    /// - Parameters:
    ///   - halfWidth: Half the width of the scale's box (600 for the 1200 pt box).
    ///   - readingHalfWidth: Half the width kept clear for the reading. The
    ///     view passes more for a long reading.
    ///   - labelWidth: Room a label needs to the right of its tick, at least.
    ///     A longer label needs its own width.
    ///   - placement: Screen points from the needle for a tick that is this
    ///     many entries away. A style that spreads its ticks (Glass lens)
    ///     passes its own; the default is the even pitch.
    func labels(
        current: Double,
        halfWidth: Double = 600,
        readingHalfWidth: Double = 80,
        labelWidth: Double = 96,
        placement: (Double) -> Double = { ScaleTape.pitch * $0 }
    ) -> [Label] {
        labelledStarts.compactMap { start -> Label? in
            let offset = placement(Double(start) - current)
            guard abs(offset) <= halfWidth else { return nil }
            // A label is drawn left-aligned at its tick, so it runs under the
            // reading from further away on the left than on the right.
            let room = max(labelWidth, Self.textWidth(groups[start], size: Self.labelSize))
            if offset > -(readingHalfWidth + room), offset < readingHalfWidth { return nil }
            return Label(text: groups[start], index: start, offset: offset)
        }
    }
}

/// How an entry's group is named for each sort.
enum ScaleGroup {
    static let unknown = "Unknown"
    static let symbols = "#"

    /// Year sort, and the year a record was added.
    static func year(_ year: Int) -> String {
        year > 0 ? String(year) : unknown
    }

    /// Artist and album sorts: the first letter, or "#" for a name that
    /// starts with a digit or a symbol. "#" sorts before "A".
    static func letter(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return symbols }
        let folded = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        guard let letter = folded.first, letter.isLetter, letter.isASCII else { return symbols }
        return String(letter)
    }

    /// Genre sort: the genre itself; a record without one goes to "Unknown",
    /// which sorts last.
    static func genre(_ genre: String?) -> String {
        guard let genre, !genre.isEmpty else { return unknown }
        return genre
    }
}
