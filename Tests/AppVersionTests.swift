import Foundation
import Testing
@testable import VinylForAppleTV

struct AppVersionTests {
    @Test func showsTheVersionAndTheBuild() {
        let line = AppVersion.string(infoDictionary: [
            "CFBundleShortVersionString": "0.18.2",
            "CFBundleVersion": "24",
        ])
        #expect(line == "Version 0.18.2 (24)")
    }

    @Test func leavesOutAMissingBuild() {
        #expect(AppVersion.string(infoDictionary: ["CFBundleShortVersionString": "0.18.2"]) == "Version 0.18.2")
        #expect(AppVersion.string(infoDictionary: [
            "CFBundleShortVersionString": "0.18.2",
            "CFBundleVersion": "",
        ]) == "Version 0.18.2")
    }

    @Test func saysUnknownWhenBothAreMissing() {
        #expect(AppVersion.string(infoDictionary: [:]) == "Version unknown")
        #expect(AppVersion.string(infoDictionary: [
            "CFBundleShortVersionString": "",
            "CFBundleVersion": "",
        ]) == "Version unknown")
        #expect(AppVersion.string(infoDictionary: nil) == "Version unknown")
    }

    @Test func keepsTheBuildWhenOnlyTheVersionIsMissing() {
        #expect(AppVersion.string(infoDictionary: ["CFBundleVersion": "24"]) == "Version unknown (24)")
    }

    @Test func appBundleSuppliesTheVersionAndTheBuild() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        #expect(!version.isEmpty)
        #expect(!build.isEmpty)
        #expect(AppVersion.current == "Version \(version) (\(build))")
    }
}
