import Foundation
import Testing
@testable import VinylForAppleTV

/// Expected values come from design-handoff/reference-python/halo_reference.py
/// (`python3 halo_reference.py`). If a constant changes there, rerun it and
/// update these.

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-4) -> Bool {
    abs(a - b) <= tolerance
}

private func close(_ colour: OKLab, _ l: Double, _ a: Double, _ b: Double, _ tolerance: Double = 1e-4) -> Bool {
    close(colour.l, l, tolerance) && close(colour.a, a, tolerance) && close(colour.b, b, tolerance)
}

private func rgb(_ hex: UInt32) -> RGB {
    RGB(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
}

/// The synthetic 32 x 32 sleeve of the reference: a red-brown field, a gold
/// band, a tan block and a dark checker. No artwork involved.
func haloTestSleeve() -> [RGB] {
    var pixels: [RGB] = []
    for y in 0..<32 {
        for x in 0..<32 {
            if (3..<8).contains(y), (2..<30).contains(x) {
                pixels.append(rgb(0xE2B455))
            } else if (14..<26).contains(y), (10..<22).contains(x), (x + y) % 2 == 0 {
                pixels.append(rgb(0x3A2C24))
            } else if y >= 26, x < 26 {
                pixels.append(rgb(0xAC7B49))
            } else {
                pixels.append(rgb(0xA5523A))
            }
        }
    }
    return pixels
}

struct OKLabTests {
    @Test func convertsFromSRGB() {
        #expect(close(OKLab(rgb(0xA5523A)), 0.535568, 0.092510, 0.069645))
        #expect(close(OKLab(rgb(0xF4C444)), 0.841118, 0.006448, 0.149261))
    }

    @Test func roundTrips() {
        let back = OKLab(rgb(0xA5523A)).rgb
        #expect(close(back.r, 0.647059) && close(back.g, 0.321569) && close(back.b, 0.227451))
    }
}

struct HaloPaletteTests {
    private let palette = HaloPalette(pixels: haloTestSleeve(), side: 32)

    @Test func keepsTheLargestColourFirstThenTheMostDifferent() {
        #expect(palette.colours.count == 3)
        #expect(close(palette.colours[0], 0.471300, 0.138765, 0.104468))   // the field, #A62300
        #expect(close(palette.colours[1], 0.680000, 0.021903, 0.185275))   // the gold band, #CE8900
        #expect(close(palette.colours[2], 0.400000, 0.023532, 0.029271))   // the dark checker, #584235
    }

    @Test func takesEdgeColoursRightBottomLeftTop() {
        #expect(close(palette.edges[0], 0.502539, 0.121034, 0.115290))
        #expect(close(palette.edges[1], 0.511642, 0.089378, 0.114040))
        #expect(close(palette.edges[2], 0.512201, 0.110969, 0.117770))
        #expect(close(palette.edges[3], 0.598957, 0.072980, 0.149956))
    }

    @Test func isTheSameEveryTime() {
        #expect(HaloPalette(pixels: haloTestSleeve(), side: 32) == palette)
    }

    @Test func holdsColoursInsideTheLimits() {
        for colour in palette.colours + palette.edges {
            #expect(HaloPalette.lightnessRange.contains(colour.l))
            #expect(colour.chroma <= HaloPalette.maximumChroma + 1e-9)
        }
        // A bright, strong yellow is pulled down on both counts.
        let toned = HaloPalette.toned(OKLab(rgb(0xFFE000)))
        #expect(close(toned.l, 0.68))
        #expect(close(toned.chroma, 0.21))
    }

    @Test func liftsColourButInventsNone() {
        // The field's chroma is lifted by half.
        let field = OKLab(rgb(0xA5523A))
        #expect(close(HaloPalette.toned(field).chroma, field.chroma * 1.5))
        // A grey stays grey.
        #expect(HaloPalette.toned(OKLab(rgb(0x808080))).chroma < 1e-6)
    }

    @Test func aColourfulAreaLeadsOverALargerBlackOne() {
        // Black over most of the sleeve, a blue block over under a fifth of it.
        var pixels = [RGB](repeating: RGB(r: 0.03, g: 0.03, b: 0.03), count: 32 * 32)
        for y in 20..<32 {
            for x in 0..<16 {
                pixels[y * 32 + x] = RGB(r: 0.1, g: 0.45, b: 0.75)
            }
        }
        let main = HaloPalette(pixels: pixels, side: 32).main
        #expect(close(main, 0.479585, -0.071289, -0.197529))   // the blue, #0059CC
        // A grey counts for little, the field for ten times as much.
        #expect(close(HaloPalette.colourWeight(OKLab(rgb(0x808080))), 0.15, 1e-3))
        #expect(close(HaloPalette.colourWeight(OKLab(rgb(0xA5523A))), 1.597443, 1e-3))
    }

    @Test func blendsEdgeColoursByDirection() {
        #expect(palette.edgeColour(at: 0) == palette.edges[0])
        #expect(close(palette.edgeColour(at: .pi / 2), 0.511642, 0.089378, 0.114040))
        let between = palette.edgeColour(at: .pi / 4)
        #expect(close(between.l, (0.502539 + 0.511642) / 2))
        // A full turn comes back to the right edge.
        #expect(close(palette.edgeColour(at: 2 * .pi + 0.0001), 0.502539, 0.121034, 0.115290, 1e-3))
    }

    @Test func aFlatSleeveGivesOneColourThreeTimes() {
        let flat = HaloPalette(pixels: [RGB](repeating: rgb(0x808080), count: 32 * 32), side: 32)
        #expect(flat.colours[0] == flat.colours[1] && flat.colours[1] == flat.colours[2])
    }
}

struct HaloFieldTests {
    private let palette = HaloPalette(pixels: haloTestSleeve(), side: 32)

    @Test func rimBreathesAroundHalf() {
        #expect(close(HaloField.rimLevel(at: 0), 0.5))
        #expect(close(HaloField.rimLevel(at: 12.5), 0.573910))
        #expect(close(HaloField.rimLevel(at: 10), 0.58) && close(HaloField.rimLevel(at: 30), 0.42))
    }

    @Test func patchesAtTheStart() {
        let patches = HaloField.patches(at: 0, palette: palette)
        #expect(patches.count == 7)
        #expect(close(patches[0].dx, 300) && close(patches[0].dy, 0) && close(patches[0].opacity, 0))
        #expect(close(patches[0].radius, 174.9440, 1e-3))
        #expect(close(patches[3].dx, 473.5462, 1e-3) && close(patches[3].dy, -617.6572, 1e-3))
        #expect(close(patches[3].radius, 268.7422, 1e-3) && close(patches[3].opacity, 0.182482))
        #expect(close(patches[3].colour, 0.476344, 0.136126, 0.106258))
    }

    @Test func patchesLater() {
        let patches = HaloField.patches(at: 12.5, palette: palette)
        #expect(close(patches[0].dx, 505.0294, 1e-3) && close(patches[0].dy, 171.4344, 1e-3))
        #expect(close(patches[0].radius, 211.3907, 1e-3) && close(patches[0].opacity, 0.588583))
        #expect(close(patches[0].colour, 0.491971, 0.123589, 0.111057))
        #expect(close(patches[3].dx, 375.4149, 1e-3) && close(patches[3].dy, -251.0651, 1e-3))
        #expect(close(patches[3].opacity, 0.404076))
    }

    @Test func aPatchFadesAcrossItsBlurredEdge() {
        // Whole well inside, a half on the disc's edge, gone well outside.
        #expect(HaloField.patchEdge(distance: 0, radius: 600) > 0.999)
        #expect(abs(HaloField.patchEdge(distance: 300, radius: 300) - 0.5) < 1e-12)
        // One blur (150 pt) outside the edge: 15.87% is left.
        #expect(abs(HaloField.patchEdge(distance: 450, radius: 300) - 0.158655) < 1e-5)
        // The patch is drawn out to three blurs past its edge, where 0.13% is left.
        let reach = HaloField.patchReach(radius: 300)
        #expect(reach == 750)
        #expect(HaloField.patchEdge(distance: reach, radius: 300) < 0.0014)
    }

    @Test func noPatchIsEverStrongerThanTheLimit() {
        for step in 0..<600 {
            for patch in HaloField.patches(at: Double(step) * 0.5, palette: palette) {
                #expect(patch.opacity >= 0 && patch.opacity <= HaloField.patchStrength + 1e-9)
                #expect(patch.progress >= 0 && patch.progress < 1)
            }
        }
    }
}

struct TideTests {
    @Test func swellsAndDrawsBack() {
        #expect(close(Tide.reach(running: 0), 0))
        #expect(close(Tide.reach(running: 10), 0.156978))
        #expect(close(Tide.reach(running: 45), 0.971716))
        #expect(close(Tide.reach(running: 67.5), 0.515307))
    }

    @Test func staysBetweenLowAndHigh() {
        for step in 0..<400 {
            let reach = Tide.reach(running: Double(step) * 0.5)
            #expect(reach >= 0 && reach <= 1)
        }
    }
}

struct CoverMotionTests {
    @Test func theSleeveNeverDriftsFurtherThanEightPoints() {
        #expect(CoverMotion.furthest < 8)
        #expect(CoverMotion.furthest > 7)
    }

    @Test func thePathTakesFourMinutesToRepeat() {
        #expect(CoverMotion.repeatsAfter == 240)
        // The two drifts have different periods, so the path loops.
        #expect(CoverMotion.periodAcross != CoverMotion.periodUpDown)
    }

    @Test func theBreathingIsThreePercentOverAMinute() {
        #expect(CoverMotion.breath == 1.03)
        #expect(CoverMotion.breathPeriod == 60)
    }
}
