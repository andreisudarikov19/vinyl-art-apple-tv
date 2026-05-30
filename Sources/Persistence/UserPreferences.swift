import Foundation
import SwiftData

enum GalleryLayout: String, Codable, CaseIterable, Sendable {
    case grid
    // Stored rawValue stays "carousel" so preferences saved before the
    // CoverFlow rename still decode.
    case coverFlow = "carousel"
}

enum GallerySort: String, Codable, CaseIterable, Sendable {
    case recentlyAdded
    case artist
    case album
    case year
}

/// Single-row settings store for the install. Discogs credentials live in
/// the Keychain; this holds the non-secret state the app needs across
/// launches.
@Model
final class UserPreferences {
    var discogsUsername: String

    /// Timestamp of the last successful collection sync; nil means the
    /// library has never been built. Drives delta refresh.
    var lastSyncDate: Date?

    var galleryLayout: GalleryLayout
    var gallerySort: GallerySort

    /// When true, the halo engages on its own after a per-mode idle period.
    /// When false, the user controls it manually via the pill on the
    /// cover-focused screen (and CoverFlow shows no halo at all).
    var haloAutoEngage: Bool = true

    init(
        discogsUsername: String = "",
        lastSyncDate: Date? = nil,
        galleryLayout: GalleryLayout = .coverFlow,
        gallerySort: GallerySort = .recentlyAdded,
        haloAutoEngage: Bool = true
    ) {
        self.discogsUsername = discogsUsername
        self.lastSyncDate = lastSyncDate
        self.galleryLayout = galleryLayout
        self.gallerySort = gallerySort
        self.haloAutoEngage = haloAutoEngage
    }
}

extension UserPreferences {
    /// Fetches the single preferences row, creating and inserting it on
    /// first access.
    static func current(in context: ModelContext) -> UserPreferences {
        if let existing = try? context.fetch(FetchDescriptor<UserPreferences>()).first {
            return existing
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        return prefs
    }
}
