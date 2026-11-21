import Testing
@testable import VinylForAppleTV

struct HaloEntryRampTests {
    @Test func startsAtZeroWhenEngaged() {
        #expect(haloEntryRamp(elapsed: 0, fadeIn: 3) == 0)
    }

    @Test func risesLinearlyAcrossTheFadeIn() {
        #expect(haloEntryRamp(elapsed: 1.5, fadeIn: 3) == 0.5)
    }

    @Test func holdsAtOneOnceTheFadeInIsDone() {
        #expect(haloEntryRamp(elapsed: 3, fadeIn: 3) == 1)
        #expect(haloEntryRamp(elapsed: 60, fadeIn: 3) == 1)
    }

    @Test func clampsNegativeElapsedToZero() {
        #expect(haloEntryRamp(elapsed: -2, fadeIn: 3) == 0)
    }

    @Test func zeroFadeInIsAlreadyFullyIn() {
        #expect(haloEntryRamp(elapsed: 0, fadeIn: 0) == 1)
    }
}
