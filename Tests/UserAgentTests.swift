import Foundation
import Testing
@testable import VinylForAppleTV

struct UserAgentTests {
    @Test func namesTheVersionAndTheSupportPage() {
        let userAgent = UserAgent.string(infoDictionary: ["CFBundleShortVersionString": "0.18.2"])
        #expect(userAgent == "VinylForAppleTV/0.18.2 ( https://andreisudarikov19.github.io/vinyl-art-apple-tv/support.html )")
    }

    @Test func leavesOutAMissingVersion() {
        let expected = "VinylForAppleTV ( https://andreisudarikov19.github.io/vinyl-art-apple-tv/support.html )"
        #expect(UserAgent.string(infoDictionary: [:]) == expected)
        #expect(UserAgent.string(infoDictionary: ["CFBundleShortVersionString": ""]) == expected)
        #expect(UserAgent.string(infoDictionary: nil) == expected)
    }

    @Test func appBundleSuppliesAVersion() {
        #expect(!UserAgent.app.hasPrefix("VinylForAppleTV/"))
    }
}
