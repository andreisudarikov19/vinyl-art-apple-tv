import Foundation
import SwiftData
import Testing
@testable import VinylForAppleTV

struct PersistenceControllerTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeRelease() -> CachedRelease {
        CachedRelease(
            releaseId: 1,
            instanceId: 1,
            title: "Title",
            artistDisplayName: "Artist",
            year: 2024,
            dateAdded: .now,
            discogsCoverURL: "https://example.com/cover.jpg",
            thumbURL: "https://example.com/thumb.jpg"
        )
    }

    @Test func corruptStoreIsReplacedWithAFreshOneOnDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "x.store")
        let garbage = Data("not a SQLite database".utf8)
        try garbage.write(to: url)

        do {
            let context = ModelContext(PersistenceController.makeContainer(at: url))
            context.insert(makeRelease())
            try context.save()
        }
        #expect(try Data(contentsOf: url) != garbage)

        let reopened = try ModelContainer(
            for: PersistenceController.schema,
            configurations: ModelConfiguration(schema: PersistenceController.schema, url: url)
        )
        let stored = try ModelContext(reopened).fetch(FetchDescriptor<CachedRelease>())
        #expect(stored.map(\.releaseId) == [1])
    }
}
