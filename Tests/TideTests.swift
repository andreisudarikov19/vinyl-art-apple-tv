import CoreGraphics
import Foundation
import Testing
@testable import VinylForAppleTV

/// Expected values come from design-handoff/specs/06-ambient-tide.md and the
/// formulas in Tide.swift; the reach figures are worked out from those formulas.

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-3) -> Bool {
    abs(a - b) <= tolerance
}

private func close(_ a: OKLab, _ b: OKLab, _ tolerance: Double = 1e-6) -> Bool {
    close(a.l, b.l, tolerance) && close(a.a, b.a, tolerance) && close(a.b, b.b, tolerance)
}

private let screen = CGSize(width: 1920, height: 1080)
private let sampleMain = OKLab(l: 0.5, a: 0.05, b: 0.04)

struct TideReachTests {
    @Test func startsAtLowTide() {
        #expect(Tide.reach(running: 0) == 0)
    }

    @Test func reachesNearHighTideAfterHalfThePeriod() {
        // 1 - 0.04 * 0.7071 from the lapping at 45 s.
        #expect(close(Tide.reach(running: 45), 0.9717))
    }

    @Test func lapsAtFortyPerCentOfTheReachAfterOneFullSwell() {
        // The swell is back at zero at 90 s; the lapping is at its peak.
        #expect(close(Tide.reach(running: 90), 0.04))
    }

    @Test func staysWithinLowAndHighTide() {
        for step in 0..<2000 {
            let reach = Tide.reach(running: Double(step) * 0.5)
            #expect(reach >= 0 && reach <= 1)
        }
    }
}

struct TideClockTests {
    private let origin = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func countsOnlyWhileMoving() {
        var clock = TideClock()
        clock.start(at: origin)
        clock.stop(at: origin.addingTimeInterval(10))
        #expect(clock.running(at: origin.addingTimeInterval(500)) == 10)
    }

    @Test func resumesWhereItStopped() {
        var clock = TideClock()
        clock.start(at: origin)
        clock.stop(at: origin.addingTimeInterval(10))
        clock.start(at: origin.addingTimeInterval(30))
        #expect(clock.running(at: origin.addingTimeInterval(35)) == 15)
        #expect(clock.isMoving)
    }

    @Test func aStopWhileStoppedChangesNothing() {
        var clock = TideClock()
        clock.stop(at: origin)
        #expect(clock.running(at: origin.addingTimeInterval(5)) == 0)
        #expect(!clock.isMoving)
    }
}

struct TideTimingTests {
    @Test func startsAtTheSpecTimes() {
        #expect(TideTiming.galleryIdle == 60)
        #expect(TideTiming.trackListIdle == 15)
    }

    @Test func fadesInAtTheSpecTimes() {
        #expect(TideTiming.galleryFadeIn == 3)
        #expect(TideTiming.trackListFadeIn == 4)
    }

    @Test func switchesDefaultAsSpecified() {
        let settings = HaloSettings()
        #expect(settings.gallery == .on)
        #expect(settings.trackList == .off)
    }

    @Test func aGalleryUpgraderWithTheHaloOffGetsNoTide() {
        let settings = HaloSettings.migrated(fromAutoEngage: false)
        #expect(settings.gallery == .off)
        #expect(settings.trackList == .off)
    }
}

struct TideGeometryTests {
    @Test func fixedRadiiAreTheLowAndHighEnds() {
        let gallery = TideShape.gallery
        #expect(gallery.radii(reach: 0, in: screen) == CGSize(width: 820, height: 600))
        let trackList = TideShape.trackList
        #expect(trackList.radii(reach: 0, in: screen) == CGSize(width: 1050, height: 760))
        #expect(trackList.radii(reach: 1, in: screen) == CGSize(width: 2400, height: 1600))
    }

    @Test func galleryCentreIsFiftyAndFortyOnePerCent() {
        let centre = TideShape.gallery.centre(in: screen)
        #expect(close(centre.x, 960, 1e-9) && close(centre.y, 442.8, 1e-9))
        #expect(TideShape.trackList.centre(in: screen) == .zero)
    }

    @Test func farthestCornerKeepsTheClosestSideProportions() {
        let centre = TideShape.gallery.centre(in: screen)
        let radii = TideShape.farthestCornerRadii(centre: centre, size: screen)
        // The closest side is 960 across and 442.8 down.
        #expect(close(radii.width / radii.height, 960 / 442.8, 1e-6))
    }

    @Test func farthestCornerPassesThroughTheFarthestCorner() {
        let centre = TideShape.gallery.centre(in: screen)
        let radii = TideShape.farthestCornerRadii(centre: centre, size: screen)
        // The far corner, bottom left or right, is 960 across and 637.2 down.
        let onEllipse = pow(960 / radii.width, 2) + pow(637.2 / radii.height, 2)
        #expect(close(onEllipse, 1, 1e-6))
    }

    @Test func galleryHighTideReachesTheFarthestCorner() {
        let radii = TideShape.gallery.radii(reach: 1, in: screen)
        #expect(close(radii.height, 776.2, 0.5))
        #expect(close(radii.width, 1682.4, 0.5))
    }
}

struct TideStopTests {
    @Test func stopsRunFromCentreToInk() {
        for shape in [TideShape.gallery, TideShape.trackList] {
            for reach in [0.0, 0.5, 1.0] {
                let stops = shape.stops(reach: reach, main: sampleMain)
                #expect(stops.first?.location == 0)
                #expect(stops.last?.location == 1)
                #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location < $1.location })
            }
        }
    }

    @Test func theCentreIsTheSleevesMainAtLowTide() {
        let stops = TideShape.gallery.stops(reach: 0, main: sampleMain)
        #expect(close(stops[0].colour, sampleMain))
    }

    @Test func inkStaysInkAtTheEdge() {
        let ink = OKLab(RGB(r: 0x0B / 255.0, g: 0x0A / 255.0, b: 0x08 / 255.0))
        for shape in [TideShape.gallery, TideShape.trackList] {
            for reach in [0.0, 1.0] {
                let edge = shape.stops(reach: reach, main: sampleMain).last
                #expect(edge.map { close($0.colour, ink, 1e-4) } == true)
            }
        }
    }

    @Test func colourBetweenStopsIsBlended() {
        let stops = [
            TideColourStop(location: 0, colour: OKLab(l: 0, a: 0, b: 0)),
            TideColourStop(location: 1, colour: OKLab(l: 1, a: 0, b: 0)),
        ]
        #expect(close(TideShape.colour(at: 0.25, in: stops), OKLab(l: 0.25, a: 0, b: 0)))
        #expect(close(TideShape.colour(at: 2, in: stops), OKLab(l: 1, a: 0, b: 0)))
    }
}
