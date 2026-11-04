import Foundation
import os
import SwiftData

/// Central place to build the app's SwiftData container so the schema is
/// declared once and shared by the app and previews.
enum PersistenceController {
    static let schema = Schema([
        CachedRelease.self,
        UserPreferences.self,
    ])

    /// The on-disk container backing the running app, at SwiftData's default
    /// store location.
    static let shared: ModelContainer = makeContainer(at: ModelConfiguration(schema: schema).url)

    /// An ephemeral container for SwiftUI previews and tests.
    static let preview: ModelContainer = makeInMemoryContainer()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VinylForAppleTV",
        category: "Persistence"
    )

    /// Opens the on-disk store at `url`. The store only caches Discogs data,
    /// so if it can't be opened, because the file is corrupt or a migration
    /// failed, its files are deleted and a fresh store takes their place. The
    /// app then builds the library as on first run, and the Discogs sign-in
    /// in the Keychain is untouched. This also resets `UserPreferences`, such
    /// as layout, sort and halo settings, since they live in the same store.
    /// If even a fresh store can't be created, e.g. for lack of space or
    /// permission, the library is kept in memory and rebuilt on each launch.
    static func makeContainer(at url: URL) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Couldn't open the store, deleting it: \(String(describing: error), privacy: .public)")
        }
        deleteStore(at: url)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            logger.error("Couldn't create a fresh store, keeping the library in memory: \(String(describing: error), privacy: .public)")
            return makeInMemoryContainer()
        }
    }

    private static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Removes the SQLite store at `url` and its `-wal` and `-shm` sidecars,
    /// leaving the directory around them alone.
    private static func deleteStore(at url: URL) {
        let directory = url.deletingLastPathComponent()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: directory.appending(path: url.lastPathComponent + suffix))
        }
    }
}
