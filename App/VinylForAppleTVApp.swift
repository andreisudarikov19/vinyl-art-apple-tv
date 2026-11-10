import SwiftData
import SwiftUI

@main
struct VinylForAppleTVApp: App {
    init() {
        // Runs before the scene's model container creates the store, so its
        // absence still marks a fresh install, and before RootView reads the
        // sign-in.
        try? DiscogsCredentialsStore.standard.removeSignInLeftByAnEarlierInstall(
            defaults: .standard,
            appDataExists: FileManager.default.fileExists(atPath: PersistenceController.storeURL.path(percentEncoded: false))
        )

        // The manual-mode halo pill persists across navigations within a
        // session but resets to OFF on every app launch (locked design).
        // @AppStorage handles the in-session persistence; this clears it
        // on launch.
        UserDefaults.standard.set(false, forKey: "haloPillEngaged")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(PersistenceController.shared)
    }
}
