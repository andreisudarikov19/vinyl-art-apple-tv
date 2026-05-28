import Foundation
import SwiftData

/// Central place to build the app's SwiftData container so the schema is
/// declared once and shared by the app and previews.
enum PersistenceController {
    static let schema = Schema([
        CachedRelease.self,
        UserPreferences.self,
    ])

    /// The on-disk container backing the running app.
    static let shared: ModelContainer = makeContainer(inMemory: false)

    /// An ephemeral container for SwiftUI previews and tests.
    static let preview: ModelContainer = makeContainer(inMemory: true)

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
