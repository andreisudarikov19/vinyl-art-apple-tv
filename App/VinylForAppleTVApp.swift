import SwiftData
import SwiftUI

@main
struct VinylForAppleTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(PersistenceController.shared)
    }
}
