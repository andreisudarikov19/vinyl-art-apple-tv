import Foundation
import Testing
@testable import VinylForAppleTV

struct ScaleIdleLookTests {
    @Test func fullyInUseEverythingIsFullBright() {
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: 0) == 1)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 0) == 1)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.needle, idle: 0) == 1)
    }

    @Test func idleDropsTheTapeToThirtyAndTheReadingToSeventyAndKeepsTheNeedleLit() {
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: 1) - 0.3) < 1e-9)
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 1) - 0.7) < 1e-9)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.needle, idle: 1) == 1)
    }

    @Test func theNeedlesOwnGlowStaysAtIdle() {
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.glow, idle: 1) == 1)
    }

    @Test func thePathBetweenUseAndIdleIsLinear() {
        // Halfway through the 0.8 s change, a level sits halfway between its two ends.
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 0.5) - 0.85) < 1e-9)
    }

    @Test func inUseTheTapeRunsTheWholeBox() {
        for x in [0.0, 100, 600, 1100, 1200] {
            #expect(ScaleIdleLook.tapeReach(at: x, width: 1200, idle: 0) == 1)
        }
    }

    @Test func idleDrawsTheTapeInTowardTheNeedle() {
        // Gone within 20% of the box from either end (240 pt of 1200).
        #expect(ScaleIdleLook.tapeReach(at: 0, width: 1200, idle: 1) == 0)
        #expect(ScaleIdleLook.tapeReach(at: 240, width: 1200, idle: 1) == 0)
        #expect(ScaleIdleLook.tapeReach(at: 960, width: 1200, idle: 1) == 0)
        // Whole from 42% (504 pt), and at the needle.
        #expect(abs(ScaleIdleLook.tapeReach(at: 504, width: 1200, idle: 1) - 1) < 1e-9)
        #expect(ScaleIdleLook.tapeReach(at: 600, width: 1200, idle: 1) == 1)
        // Half way through the fade (31%, 372 pt), half is left.
        #expect(abs(ScaleIdleLook.tapeReach(at: 372, width: 1200, idle: 1) - 0.5) < 1e-9)
        #expect(abs(ScaleIdleLook.tapeReach(at: 828, width: 1200, idle: 1) - 0.5) < 1e-9)
    }
}
