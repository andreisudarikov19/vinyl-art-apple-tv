import Foundation
import Testing
@testable import VinylForAppleTV

struct UserPreferencesTests {
    @Test func libraryBelongsOnlyToTheAccountThatBuiltIt() {
        let built = UserPreferences(discogsUsername: "tester", lastSyncDate: .now)
        #expect(built.hasLibrary(for: "tester"))
        #expect(!built.hasLibrary(for: "someone-else"))
    }

    @Test func neverBuiltLibraryBelongsToNobody() {
        let fresh = UserPreferences()
        #expect(!fresh.hasLibrary(for: "tester"))
        #expect(!fresh.hasLibrary(for: ""))
    }
}
