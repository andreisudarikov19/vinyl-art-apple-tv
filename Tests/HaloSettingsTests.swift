import Foundation
import SwiftData
import Testing
@testable import VinylForAppleTV

struct HaloSettingsTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func newInstallDefaultsMatchTheSpec() {
        let settings = HaloSettings()
        #expect(settings.gallery == .on)
        #expect(settings.trackList == .off)
        #expect(settings.coverView == .manual)
        #expect(settings.manualCoverHaloOn)
        #expect(settings.coverHaloIsOn)
    }

    @Test func upgraderWithAutoEngageOnKeepsTheDefaults() {
        let settings = HaloSettings.migrated(fromAutoEngage: true)
        #expect(settings == HaloSettings())
        #expect(settings.gallery == .on)
        #expect(settings.coverView == .manual)
        #expect(settings.manualCoverHaloOn)
    }

    @Test func upgraderWithAutoEngageOffGetsNoGalleryHaloAndAManualPillOff() {
        let settings = HaloSettings.migrated(fromAutoEngage: false)
        #expect(settings.gallery == .off)
        #expect(settings.trackList == .off)
        #expect(settings.coverView == .manual)
        #expect(!settings.manualCoverHaloOn)
        #expect(!settings.coverHaloIsOn)
    }

    @Test func coverHaloFollowsTheCoverViewChoice() {
        var settings = HaloSettings()
        settings.coverView = .on
        settings.manualCoverHaloOn = false
        #expect(settings.coverHaloIsOn)

        settings.coverView = .off
        settings.manualCoverHaloOn = true
        #expect(!settings.coverHaloIsOn)

        settings.coverView = .manual
        settings.manualCoverHaloOn = false
        #expect(!settings.coverHaloIsOn)
        settings.manualCoverHaloOn = true
        #expect(settings.coverHaloIsOn)
    }

    @Test func selectingACoverViewCyclesOnOffManual() {
        var settings = HaloSettings()
        settings.coverView = .on
        settings.cycleCoverView()
        #expect(settings.coverView == .off)
        settings.cycleCoverView()
        #expect(settings.coverView == .manual)
        settings.cycleCoverView()
        #expect(settings.coverView == .on)
    }

    @Test func existingStoreOpensWithTheMigratedValuesFromAutoEngageOff() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "x.store")

        // A row as an older build wrote it: only haloAutoEngage, no halo settings.
        do {
            let container = PersistenceController.makeContainer(at: url)
            let context = ModelContext(container)
            context.insert(UserPreferences(discogsUsername: "tester", haloAutoEngage: false))
            try context.save()
        }

        let reopened = PersistenceController.makeContainer(at: url)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<UserPreferences>())
        #expect(rows.count == 1)
        #expect(rows.first?.storedHaloSettings == nil)
        #expect(rows.first?.haloSettings == HaloSettings.migrated(fromAutoEngage: false))
        #expect(rows.first?.haloSettings.gallery == .off)
        #expect(rows.first?.haloSettings.coverHaloIsOn == false)
    }

    @Test func existingStoreOpensWithTheMigratedValuesFromAutoEngageOn() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "x.store")

        do {
            let context = ModelContext(PersistenceController.makeContainer(at: url))
            context.insert(UserPreferences(discogsUsername: "tester", haloAutoEngage: true))
            try context.save()
        }

        let reopened = PersistenceController.makeContainer(at: url)
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<UserPreferences>())
        #expect(rows.first?.haloSettings == HaloSettings.migrated(fromAutoEngage: true))
    }

    @Test func storedHaloSettingsSurviveReopeningAndOverrideHaloAutoEngage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "x.store")

        do {
            let context = ModelContext(PersistenceController.makeContainer(at: url))
            let prefs = UserPreferences(haloAutoEngage: false)
            prefs.haloSettings.trackList = .on
            prefs.haloSettings.coverView = .off
            context.insert(prefs)
            try context.save()
        }

        let reopened = PersistenceController.makeContainer(at: url)
        let context = ModelContext(reopened)
        let prefs = try #require(try context.fetch(FetchDescriptor<UserPreferences>()).first)
        #expect(prefs.haloSettings.trackList == .on)
        #expect(prefs.haloSettings.coverView == .off)
        // The stored value is kept, so the old switch no longer changes it.
        prefs.haloAutoEngage = true
        #expect(prefs.haloSettings.gallery == .off)
        #expect(prefs.haloSettings.coverView == .off)
    }
}
