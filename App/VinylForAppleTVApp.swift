import SwiftData
import SwiftUI

@main
struct VinylForAppleTVApp: App {
    init() {
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
