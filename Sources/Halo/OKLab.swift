import Foundation

/// A colour in OKLab (Björn Ottosson). The halo mixes and limits colours here
/// because equal steps look equal, and a blend between two hues stays a colour
/// instead of passing through grey.
///
/// Port of design-handoff/reference-python/halo_reference.py. Keep the two in step.
struct OKLab: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    var chroma: Double { (a * a + b * b).squareRoot() }

    /// From sRGB components in 0...1.
    init(_ rgb: RGB) {
        let r = Self.linear(rgb.r), g = Self.linear(rgb.g), bl = Self.linear(rgb.b)
        let lc = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let mc = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let sc = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        l = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc
        a = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc
        b = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
    }

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    /// Back to sRGB, clamped to 0...1.
    var rgb: RGB {
        let lc = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let mc = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let sc = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return RGB(
            r: Self.encoded(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc),
            g: Self.encoded(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc),
            b: Self.encoded(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
        )
    }

    static func lerp(_ p: OKLab, _ q: OKLab, t: Double) -> OKLab {
        OKLab(l: p.l + (q.l - p.l) * t, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t)
    }

    func distanceSquared(to other: OKLab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> Double {
        let c = min(1, max(0, value))
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}
