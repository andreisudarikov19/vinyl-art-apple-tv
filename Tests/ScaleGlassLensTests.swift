import Foundation
import Testing
@testable import VinylForAppleTV

struct ScaleGlassLensTests {
    @Test func ticksAreCentrePitchApartAtTheNeedleAndEdgePitchAtTheEdges() {
        // One entry either side of the needle: 44 pt, a little less for the
        // tanh curve, never more.
        let first = GlassLens.offset(entries: 1)
        #expect(first > 43 && first < 44)
        // Beyond the lens the spacing is the plain 16 pt pitch.
        let edge = GlassLens.edgeEntries
        #expect(abs(GlassLens.offset(entries: edge + 1) - GlassLens.offset(entries: edge) - 16) < 1e-9)
    }

    @Test func theLensEdgeFallsOnTheEdgeEntry() {
        #expect(abs(GlassLens.offset(entries: GlassLens.edgeEntries) - GlassLens.halfWidth) < 1e-9)
        #expect(abs(GlassLens.offset(entries: -GlassLens.edgeEntries) + GlassLens.halfWidth) < 1e-9)
    }

    @Test func offsetsIncreaseAndAreSymmetric() {
        var previous = GlassLens.offset(entries: 0)
        #expect(previous == 0)
        for step in 1...60 {
            let current = GlassLens.offset(entries: Double(step) * 0.5)
            #expect(current > previous)
            #expect(GlassLens.offset(entries: -Double(step) * 0.5) == -current)
            previous = current
        }
    }

    @Test func spacingNeverDropsBelowTheEdgePitch() {
        // The tape is always at least 16 pt a tick, so the box fits its ticks.
        for step in 0..<400 {
            let entries = Double(step) * 0.25
            let gap = GlassLens.offset(entries: entries + 0.25) - GlassLens.offset(entries: entries)
            #expect(gap >= 0.25 * GlassLens.edgePitch - 1e-9)
        }
    }

    @Test func weightIsOneAtTheNeedleAndZeroAtTheEdge() {
        #expect(GlassLens.weight(offset: 0) == 1)
        #expect(GlassLens.weight(offset: GlassLens.halfWidth) == 0)
        #expect(GlassLens.weight(offset: 900) == 0)
        #expect(GlassLens.weight(offset: -GlassLens.halfWidth / 2) == 0.75)
    }

    @Test func scaleStylesAndTheDefault() {
        #expect(ScaleStyle.allCases == [.slideRule, .glassLens])
        #expect(UserPreferences().scaleStyle == .slideRule)
    }
}
