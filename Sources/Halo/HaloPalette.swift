import Foundation

/// The colours the halo and the tide take from a sleeve.
///
/// The sleeve's pixels are grouped into five colours and three are kept: the
/// one that counts for most, and the two most different ones that still
/// cover a real share of the sleeve. A colourful group counts for more than
/// a grey one, so the black, white and grey areas of a sleeve do not decide
/// the light. Every colour then has its chroma lifted a little and is held
/// inside lightness and chroma limits, so the light is rich in colour and
/// never outshines the sleeve.
///
/// Port of design-handoff/reference-python/halo_reference.py. Keep the two in step.
struct HaloPalette: Equatable, Sendable {
    /// Three colours: the main one first.
    let colours: [OKLab]
    /// The colour of each side of the sleeve, for the rim and for where a
    /// drifting patch starts: right, bottom, left, top (angle 0, 90, 180 and
    /// 270 degrees with y pointing down).
    let edges: [OKLab]

    var main: OKLab { colours[0] }

    static let clusterCount = 5
    static let iterations = 20
    /// An accent must cover at least this share of the sleeve.
    static let minimumArea = 0.04
    static let maximumChroma = 0.21
    /// The light is a little stronger in colour than the sleeve.
    static let chromaBoost = 1.5
    static let lightnessScale = 0.88
    static let lightnessRange = 0.40...0.68
    /// How much more a colourful pixel or group counts than a grey one when
    /// the halo picks its colours: `colourBase + chroma / colourSpan`.
    static let colourBase = 0.15
    static let colourSpan = 0.08

    /// - Parameters:
    ///   - pixels: The sleeve scaled down to `side` by `side`, row by row,
    ///     sRGB in 0...1. The app uses 32.
    init(pixels: [RGB], side: Int) {
        precondition(pixels.count == side * side && side >= 4)
        let labs = pixels.map { OKLab($0) }
        colours = Self.chosenColours(labs)
        edges = Self.edgeColours(labs, side: side)
    }

    init(colours: [OKLab], edges: [OKLab]) {
        self.colours = colours
        self.edges = edges
    }

    /// The edge colour for a direction, blended between the two nearest sides.
    func edgeColour(at angle: Double) -> OKLab {
        var theta = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if theta < 0 { theta += 2 * .pi }
        let position = theta / (.pi / 2)
        let lower = Int(position.rounded(.down)) % 4
        return OKLab.lerp(edges[lower], edges[(lower + 1) % 4], t: position - position.rounded(.down))
    }

    /// How much a colour counts when the halo picks: a colourful one counts
    /// for more than a grey one.
    static func colourWeight(_ colour: OKLab) -> Double {
        colourBase + colour.chroma / colourSpan
    }

    /// Makes a colour fit for the halo: its chroma lifted by `chromaBoost`
    /// and held under `maximumChroma`, its lightness held inside the limits.
    /// A grey stays grey: nothing is invented.
    static func toned(_ colour: OKLab) -> OKLab {
        let chroma = colour.chroma
        let scale = chroma > 1e-9 ? min(chromaBoost, maximumChroma / chroma) : 1
        let lightness = min(lightnessRange.upperBound, max(lightnessRange.lowerBound, lightnessScale * colour.l))
        return OKLab(l: lightness, a: colour.a * scale, b: colour.b * scale)
    }

    // MARK: - Clustering

    /// Deterministic k-means, so the same sleeve always gives the same halo:
    /// the first centre is the pixel nearest the mean, each further centre is
    /// the pixel farthest from the centres chosen so far. Ties go to the
    /// lowest index.
    static func clusters(_ labs: [OKLab]) -> (centres: [OKLab], area: [Double]) {
        let count = Double(labs.count)
        var mean = OKLab(l: 0, a: 0, b: 0)
        for p in labs { mean.l += p.l; mean.a += p.a; mean.b += p.b }
        mean = OKLab(l: mean.l / count, a: mean.a / count, b: mean.b / count)

        var first = 0
        var best = Double.infinity
        for (i, p) in labs.enumerated() {
            let d = p.distanceSquared(to: mean)
            if d < best { best = d; first = i }
        }
        var centres = [labs[first]]
        while centres.count < clusterCount {
            var far = 0
            var farthest = -1.0
            for (i, p) in labs.enumerated() {
                let d = centres.map { p.distanceSquared(to: $0) }.min() ?? 0
                if d > farthest { farthest = d; far = i }
            }
            centres.append(labs[far])
        }

        var assignment = [Int](repeating: 0, count: labs.count)
        for _ in 0..<iterations {
            for (i, p) in labs.enumerated() {
                var nearest = 0
                var nearestDistance = Double.infinity
                for (j, centre) in centres.enumerated() {
                    let d = p.distanceSquared(to: centre)
                    if d < nearestDistance { nearestDistance = d; nearest = j }
                }
                assignment[i] = nearest
            }
            for j in 0..<clusterCount {
                var sum = OKLab(l: 0, a: 0, b: 0)
                var members = 0.0
                for (i, p) in labs.enumerated() where assignment[i] == j {
                    sum.l += p.l; sum.a += p.a; sum.b += p.b
                    members += 1
                }
                if members > 0 {
                    centres[j] = OKLab(l: sum.l / members, a: sum.a / members, b: sum.b / members)
                }
            }
        }
        var area = [Double](repeating: 0, count: clusterCount)
        for j in assignment { area[j] += 1 / count }
        return (centres, area)
    }

    private static func chosenColours(_ labs: [OKLab]) -> [OKLab] {
        let (centres, area) = clusters(labs)
        // The group that counts for most: its area times its colour weight.
        let counts = (0..<clusterCount).map { area[$0] * colourWeight(centres[$0]) }
        var largest = 0
        for j in 1..<clusterCount where counts[j] > counts[largest] { largest = j }
        var order = [largest]
        while order.count < 3 {
            var pick: Int?
            var pickScore = -1.0
            for j in 0..<clusterCount where !order.contains(j) && area[j] >= minimumArea {
                let nearest = order.map { centres[j].distanceSquared(to: centres[$0]).squareRoot() }.min() ?? 0
                let score = nearest * area[j].squareRoot()
                if score > pickScore { pickScore = score; pick = j }
            }
            guard let pick else { break }
            order.append(pick)
        }
        var out = order.map { toned(centres[$0]) }
        while out.count < 3 { out.append(out[out.count - 1]) }
        return out
    }

    /// The colour of a strip a quarter of the image deep along each side: the
    /// mean of its pixels, each counted by its colour weight, then toned.
    private static func edgeColours(_ labs: [OKLab], side: Int) -> [OKLab] {
        let depth = side / 4
        func strip(_ keep: (_ x: Int, _ y: Int) -> Bool) -> OKLab {
            var sum = OKLab(l: 0, a: 0, b: 0)
            var n = 0.0
            for y in 0..<side {
                for x in 0..<side where keep(x, y) {
                    let p = labs[y * side + x]
                    let weight = colourWeight(p)
                    sum.l += p.l * weight; sum.a += p.a * weight; sum.b += p.b * weight
                    n += weight
                }
            }
            return toned(OKLab(l: sum.l / n, a: sum.a / n, b: sum.b / n))
        }
        return [
            strip { x, _ in x >= side - depth },
            strip { _, y in y >= side - depth },
            strip { x, _ in x < depth },
            strip { _, y in y < depth },
        ]
    }
}
