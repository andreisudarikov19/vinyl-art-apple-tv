import Foundation

/// The model behind the scale under the cover in the Gallery: one tick per
/// entry of the list being browsed, with a taller tick and a label where a
/// group begins. Every scale style draws from this; the styles are looks,
/// not behaviours. See design-handoff/specs/01-gallery-and-scale.md.
struct ScaleTape: Equatable, Sendable {
    /// The group of each entry, in list order: a year, a letter, a genre.
    let groups: [String]
    /// Points between neighbouring ticks on this tape. A long list sits at
    /// the closest pitch; a short one is spread so it still fills the box.
    let spacing: Double
    /// Group starts that carry a label. Decided once over the whole tape, not
    /// over what is on screen, so a label never appears or vanishes as the
    /// tape scrolls. A label is 80 pt or more from the one before it, and
    /// further still when that one is wider than that, so long genre names
    /// do not run into the next.
    let labelledStarts: [Int]
    /// `labelledStarts` again, for a quick answer per tick.
    private let labelled: Set<Int>

    /// The closest ticks ever sit: 16 pt.
    static let pitch = 16.0
    /// The widest a short tape is spread: 40 pt.
    static let widestPitch = 40.0
    /// The width of the scale's box, which a short tape is spread to fill.
    static let boxWidth = 1200.0
    /// A label is skipped if it would start within this distance of the one before it.
    static let minimumLabelGap = 80.0
    /// Labels are DM Mono Regular 25 pt and the reading DM Mono Medium 36 pt.
    static let labelSize = 25.0
    static let readingSize = 36.0
    /// Room kept between a label and the one after it, or the reading.
    static let textGap = 16.0
    /// A label nearing the reading fades out over this distance, so it does
    /// not vanish between one press and the next.
    static let labelFade = 48.0
    /// The label of the group under the needle repeats the reading, so it is
    /// shown only once its tick is this far from the needle, where it marks
    /// where the group began.
    static let ownLabelDistance = 200.0

    /// The width of a DM Mono line: 0.6 em a character.
    static func textWidth(_ text: String, size: Double) -> Double {
        Double(text.count) * 0.6 * size
    }

    /// The pitch for a list of `count` entries: the box's width shared out,
    /// held between 16 and 40 pt. 75 entries or more sit at 16 pt; 30 or
    /// fewer at 40 pt.
    static func spacing(forCount count: Int) -> Double {
        guard count > 0 else { return pitch }
        return min(widestPitch, max(pitch, boxWidth / Double(count)))
    }

    init(groups: [String]) {
        self.init(groups: groups, spacing: Self.spacing(forCount: groups.count))
    }

    init(groups: [String], spacing: Double) {
        self.groups = groups
        self.spacing = spacing
        var kept: [Int] = []
        for start in groups.indices where start == 0 || groups[start] != groups[start - 1] {
            if let last = kept.last {
                let width = Self.textWidth(groups[last], size: Self.labelSize) + Self.textGap
                let needed = max(Self.minimumLabelGap, width)
                if Double(start - last) * spacing < needed { continue }
            }
            kept.append(start)
        }
        labelledStarts = kept
        labelled = Set(kept)
    }

    struct Label: Equatable, Sendable {
        var text: String
        /// Index of the first entry of the group.
        var index: Int
        /// Points from the needle; negative is left.
        var offset: Double
        /// 1 in the open, falling to 0 as the label nears the reading.
        var opacity = 1.0
    }

    /// What kind of tick an entry gets.
    enum Tick: Equatable, Sendable {
        /// A record inside a group: 12 pt.
        case record
        /// The first record of a group whose label was skipped: 18 pt.
        case group
        /// The first record of a group that carries a label: 24 pt.
        case labelledGroup
    }

    /// The reading at the needle: the group the current entry belongs to.
    func reading(at current: Int) -> String? {
        groups.indices.contains(current) ? groups[current] : nil
    }

    /// Index of the first entry of every group.
    var groupStarts: [Int] {
        groups.indices.filter { $0 == 0 || groups[$0] != groups[$0 - 1] }
    }

    /// Whether the entry at `index` is the first of its group.
    func isGroupStart(_ index: Int) -> Bool {
        index == 0 || (groups.indices.contains(index) && groups[index] != groups[index - 1])
    }

    /// The tick of the entry at `index`. Only a group with a label gets the
    /// tall tick, so every tall tick on the tape can be read.
    func tick(at index: Int) -> Tick {
        if labelled.contains(index) { return .labelledGroup }
        return isGroupStart(index) ? .group : .record
    }

    /// Where the tick of entry `index` sits when `current` is under the needle.
    /// `current` is fractional while the tape glides between two entries.
    func offset(of index: Int, current: Double) -> Double {
        (Double(index) - current) * spacing
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
    ///     passes its own; without one, the tape's even spacing is used.
    func labels(
        current: Double,
        halfWidth: Double = 600,
        readingHalfWidth: Double = 80,
        labelWidth: Double = 96,
        placement: ((Double) -> Double)? = nil
    ) -> [Label] {
        let pitch = spacing
        let needleGroup = self.reading(at: Int(current.rounded()))
        return labelledStarts.compactMap { start -> Label? in
            let entries = Double(start) - current
            let offset = placement.map { $0(entries) } ?? pitch * entries
            guard abs(offset) <= halfWidth else { return nil }
            // A label is drawn left-aligned at its tick, so it runs under the
            // reading from further away on the left than on the right.
            let room = max(labelWidth, Self.textWidth(groups[start], size: Self.labelSize))
            let left = -(readingHalfWidth + room)
            let right = readingHalfWidth
            if offset > left, offset < right { return nil }
            // How far the label stands clear of the reading's ground.
            let clear = offset <= left ? left - offset : offset - right
            var opacity = min(1, clear / Self.labelFade)
            if groups[start] == needleGroup {
                opacity = min(opacity, (abs(offset) - Self.ownLabelDistance) / Self.labelFade)
            }
            guard opacity > 0 else { return nil }
            return Label(text: groups[start], index: start, offset: offset, opacity: opacity)
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
