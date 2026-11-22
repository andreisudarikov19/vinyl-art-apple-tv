import Foundation

/// The tide's geometry and timings, from design-handoff/specs/06-ambient-tide.md.
///
/// The tide is one ellipse of glow with colour stops. Its two ends, low tide
/// and high tide, are given as drawn for the example sleeve; `main` (the
/// sleeve's `HaloPalette.main`) takes the place of the example's main colour,
/// and every other stop keeps its darkness relative to that main colour.
/// `Tide.reach(running:)` moves the shape between the two ends.
struct TideShape: Equatable, Sendable {
    /// Where the glow is centred, as fractions of the screen's width and height.
    let origin: CGPoint
    let low: TideEnd
    let high: TideEnd
}

/// One end of the tide: its ellipse and its colour stops.
struct TideEnd: Equatable, Sendable {
    enum Radii: Equatable, Sendable {
        /// Radii in points.
        case fixed(CGSize)
        /// The ellipse with the screen's closest-side proportions that reaches the farthest corner.
        case farthestCorner
    }

    let radii: Radii
    /// Stops from the centre out. The last one is ink, at 1.
    let stops: [TideStop]
}

struct TideStop: Equatable, Sendable {
    /// Where the stop sits, 0 at the centre and 1 at the edge of the ellipse.
    let location: Double
    /// The colour drawn for the example sleeve.
    let hex: UInt32
}

/// A colour stop for a particular sleeve.
struct TideColourStop: Equatable, Sendable {
    let location: Double
    let colour: OKLab
}

extension TideShape {
    /// Theme.ink, the colour the tide fades to at the edge.
    static let inkHex: UInt32 = 0x0B0A08

    /// The Gallery: behind the centre cover, 50% across and 41% down.
    ///
    /// Larger and brighter than first drawn. In the running app the covers
    /// hide the middle of the glow, so what is seen is its outer part: the
    /// band above the covers and the light on the side covers. At high tide
    /// the sleeve's main colour now reaches 40% of the way out, where the
    /// first version was already near ink.
    static let gallery = TideShape(
        origin: CGPoint(x: 0.5, y: 0.41),
        low: TideEnd(radii: .fixed(CGSize(width: 1000, height: 700)), stops: [
            TideStop(location: 0, hex: 0x8A4A26),
            TideStop(location: 0.46, hex: 0x4A2A1C),
            TideStop(location: 0.82, hex: 0x14110D),
            TideStop(location: 1, hex: inkHex),
        ]),
        high: TideEnd(radii: .farthestCorner, stops: [
            TideStop(location: 0, hex: 0xB8672F),
            TideStop(location: 0.40, hex: 0x8A4A26),
            TideStop(location: 0.70, hex: 0x4A2A1C),
            TideStop(location: 0.90, hex: 0x1C1510),
            TideStop(location: 1, hex: inkHex),
        ])
    )

    /// The track list: centred on the top left corner.
    static let trackList = TideShape(
        origin: CGPoint(x: 0, y: 0),
        low: TideEnd(radii: .fixed(CGSize(width: 1050, height: 760)), stops: [
            TideStop(location: 0, hex: 0x5A2E1C),
            TideStop(location: 0.45, hex: 0x2E1A12),
            TideStop(location: 0.76, hex: 0x14110D),
            TideStop(location: 1, hex: inkHex),
        ]),
        high: TideEnd(radii: .fixed(CGSize(width: 2400, height: 1600)), stops: [
            TideStop(location: 0, hex: 0x6A3620),
            TideStop(location: 0.34, hex: 0x4A2819),
            TideStop(location: 0.62, hex: 0x2A1911),
            TideStop(location: 0.85, hex: 0x14110D),
            TideStop(location: 1, hex: inkHex),
        ])
    )

    /// The centre of the glow on a screen of `size`.
    func centre(in size: CGSize) -> CGPoint {
        CGPoint(x: origin.x * size.width, y: origin.y * size.height)
    }

    /// The ellipse's radii at `reach` (0 low tide, 1 high tide) on a screen of `size`.
    func radii(reach: Double, in size: CGSize) -> CGSize {
        let centre = centre(in: size)
        let low = Self.radii(of: self.low, centre: centre, size: size)
        let high = Self.radii(of: self.high, centre: centre, size: size)
        return CGSize(
            width: low.width + (high.width - low.width) * reach,
            height: low.height + (high.height - low.height) * reach
        )
    }

    /// The colour stops at `reach` for a sleeve whose main colour is `main`.
    /// Both ends are resampled at the locations of both, so they have the same
    /// stops and the morph between them is a plain blend.
    func stops(reach: Double, main: OKLab) -> [TideColourStop] {
        let reference = low.stops[0].hex
        let lowStops = Self.colourStops(of: low, main: main, reference: reference)
        let highStops = Self.colourStops(of: high, main: main, reference: reference)
        let locations = Array(Set(lowStops.map(\.location) + highStops.map(\.location))).sorted()
        return locations.map { location in
            TideColourStop(
                location: location,
                colour: OKLab.lerp(
                    Self.colour(at: location, in: lowStops),
                    Self.colour(at: location, in: highStops),
                    t: reach
                )
            )
        }
    }

    // MARK: - Pure helpers

    /// The ellipse of `end` on a screen of `size` with its glow centred at `centre`.
    static func radii(of end: TideEnd, centre: CGPoint, size: CGSize) -> CGSize {
        switch end.radii {
        case .fixed(let radii):
            radii
        case .farthestCorner:
            farthestCornerRadii(centre: centre, size: size)
        }
    }

    /// The ellipse with the closest-side proportions of the screen that passes
    /// through the farthest corner, as CSS draws `radial-gradient(ellipse farthest-corner)`.
    static func farthestCornerRadii(centre: CGPoint, size: CGSize) -> CGSize {
        let closeX = max(1, min(centre.x, size.width - centre.x))
        let closeY = max(1, min(centre.y, size.height - centre.y))
        let farX = max(centre.x, size.width - centre.x)
        let farY = max(centre.y, size.height - centre.y)
        let ratio = closeX / closeY
        let k = ((farX / ratio) * (farX / ratio) + farY * farY).squareRoot()
        return CGSize(width: ratio * k, height: k)
    }

    static func colourStops(of end: TideEnd, main: OKLab, reference: UInt32) -> [TideColourStop] {
        end.stops.map { stop in
            TideColourStop(
                location: stop.location,
                colour: sleeveColour(hex: stop.hex, reference: reference, main: main)
            )
        }
    }

    /// The example colour `hex` for a sleeve with `main`: the same darkness and
    /// chroma relative to `main` as `hex` has relative to `reference`, the
    /// example's main colour. Ink stays ink.
    static func sleeveColour(hex: UInt32, reference: UInt32, main: OKLab) -> OKLab {
        if hex == inkHex {
            return OKLab(rgb(hex))
        }
        let colour = OKLab(rgb(hex))
        let base = OKLab(rgb(reference))
        let lightness = base.l > 1e-9 ? colour.l / base.l : 1
        let chroma = base.chroma > 1e-9 ? colour.chroma / base.chroma : 1
        return OKLab(l: min(0.9, main.l * lightness), a: main.a * chroma, b: main.b * chroma)
    }

    /// Linear interpolation between stops by location, clamped at both ends.
    static func colour(at location: Double, in stops: [TideColourStop]) -> OKLab {
        guard let first = stops.first, let last = stops.last else {
            return OKLab(l: 0, a: 0, b: 0)
        }
        if location <= first.location { return first.colour }
        if location >= last.location { return last.colour }
        for (a, b) in zip(stops, stops.dropFirst()) where location <= b.location {
            let width = b.location - a.location
            let t = width > 0 ? (location - a.location) / width : 0
            return OKLab.lerp(a.colour, b.colour, t: t)
        }
        return last.colour
    }

    private static func rgb(_ hex: UInt32) -> RGB {
        RGB(
            r: Double((hex >> 16) & 0xFF) / 255,
            g: Double((hex >> 8) & 0xFF) / 255,
            b: Double(hex & 0xFF) / 255
        )
    }
}

/// What the tide's light does to the Gallery's covers while it moves
/// (design-handoff/reference/GalleryIdle.jpg). The carousel fills the row
/// from edge to edge, so the glow behind it can only be seen where it falls
/// on the covers themselves.
enum TideLight {
    /// The glow drawn again over the side covers, under the centre cover, at
    /// this strength. They sink into the tide and the centre cover stands out.
    static let spill = 0.5
    /// The spill ends above the title: full to 72% of the screen's height,
    /// gone by 80%.
    static let spillFadeStart = 0.72
    static let spillFadeEnd = 0.80
    /// A rim of light around the centre cover: a patch a little larger than
    /// the cover, blurred.
    static let rimStrength = 0.7
    static let rimBlur = 110.0
    static let rimScale = 1.12
    /// The Gallery's ink at the left and right edges gives way by this much
    /// while the tide moves, so the colour reaches the sides of the screen.
    static let sideFadeLift = 0.6

    /// The rim's colour: the sleeve's main colour, lifted and a little
    /// stronger. Its lightness is held between 0.66 and 0.82, so a dark
    /// sleeve still gets a rim that can be seen.
    static func rimColour(main: OKLab) -> OKLab {
        OKLab(l: min(0.82, max(0.66, main.l + 0.22)), a: main.a * 1.15, b: main.b * 1.15)
    }
}

/// The tide's timings, from the spec.
enum TideTiming {
    /// Gallery: seconds without a press before the tide starts.
    static let galleryIdle: TimeInterval = 30
    /// Track list: seconds without a press before the tide starts.
    static let trackListIdle: TimeInterval = 15
    static let galleryFadeIn: TimeInterval = 3
    static let trackListFadeIn: TimeInterval = 4
    /// Gallery: how fast the tide gives way to the still glow on a press. The
    /// spec does not give a number; this is the halo's fade-out today.
    static let galleryFadeOut: TimeInterval = 0.4
    /// Gallery: the tide starts this far into its swell (about a quarter of
    /// the way in and rising), so there is something to see as soon as it
    /// fades in, not half a minute later.
    static let galleryHeadStart: TimeInterval = 15
}

/// How long the tide has been moving. It counts only between `start` and
/// `stop`, so a tide that stops resumes where it stopped.
struct TideClock: Equatable, Sendable {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?

    var isMoving: Bool { startedAt != nil }

    mutating func start(at date: Date) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    mutating func stop(at date: Date) {
        guard let startedAt else { return }
        accumulated += max(0, date.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    /// Seconds the tide has been moving, as of `date`.
    func running(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}
