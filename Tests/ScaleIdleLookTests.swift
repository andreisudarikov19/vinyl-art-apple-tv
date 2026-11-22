import Foundation
import Testing
@testable import VinylForAppleTV

struct ScaleIdleLookTests {
    @Test func fullyInUseEverythingIsFullBright() {
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: 0) == 1)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 0) == 1)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.needle, idle: 0) == 1)
    }

    @Test func idleDropsTheTapeToThirtyAndTheReadingAndNeedleToSeventy() {
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.tape, idle: 1) - 0.3) < 1e-9)
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 1) - 0.7) < 1e-9)
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.needle, idle: 1) - 0.7) < 1e-9)
    }

    @Test func theNeedlesGlowIsHalvedButStillThere() {
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.glow, idle: 1) - 0.5) < 1e-9)
        #expect(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.glow, idle: 1) > 0)
    }

    @Test func thePathBetweenUseAndIdleIsLinear() {
        // Halfway through the 0.8 s change, a level sits halfway between its two ends.
        #expect(abs(ScaleIdleLook.opacity(idleLevel: ScaleIdleLook.reading, idle: 0.5) - 0.85) < 1e-9)
    }
}
