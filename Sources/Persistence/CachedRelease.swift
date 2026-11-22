import Foundation
import SwiftData

/// A vinyl release cached from the user's Discogs collection.
///
/// Stores the metadata the gallery and record header need (artist, title,
/// year, genre/style) plus cover URLs. Tracklists are intentionally not
/// cached — they're fetched lazily from Discogs when a record opens.
@Model
final class CachedRelease {
    @Attribute(.unique) var releaseId: Int
    var instanceId: Int

    var title: String
    var artistDisplayName: String
    var year: Int

    /// Parsed from Discogs `date_added`; drives "Recently added" sort and
    /// delta refresh (compared against `UserPreferences.lastSyncDate`).
    var dateAdded: Date

    var masterId: Int?
    var labelName: String?
    var catalogNumber: String?

    var genres: [String]
    var styles: [String]

    /// Cover shipped in the Discogs collection payload — always present.
    var discogsCoverURL: String
    var thumbURL: String

    /// Higher-quality cover resolved later via the Cover Art Archive
    /// pipeline. Nil until resolved; callers fall back to `discogsCoverURL`.
    var resolvedCoverURL: String?

    /// Set once the cover pipeline is done with this release, so an 800-album
    /// collection isn't re-queried against MusicBrainz on every launch. A
    /// lookup that fails for a transient reason leaves it unset.
    var coverLookupAttempted: Bool

    /// Lookups that MusicBrainz or the Cover Art Archive answered with a 429
    /// or 5xx. At `CoverArtService.maxLookupFailures` the release is marked
    /// attempted and keeps its Discogs cover. The default in the declaration
    /// lets SwiftData's lightweight migration fill it for existing stores.
    var coverLookupFailures: Int = 0

    /// The version of the cover rule (`CoverArtService.coverRuleVersion`)
    /// this release was last judged under. A release with a
    /// `resolvedCoverURL` below the current version was decided under an
    /// older rule and is judged once more. Zero for releases never judged.
    var coverRuleVersion: Int = 0

    /// A year for the album found elsewhere, for a release Discogs gives no
    /// year (`year` is 0): from the Discogs master release, or else from
    /// MusicBrainz. It is a year of the album, which need not be the year of
    /// this pressing. Zero when none was found. `ReleaseYearService` owns it.
    var albumYear: Int = 0

    /// Set once `ReleaseYearService` has a definite answer for this release,
    /// a year or none, so it isn't asked again on every launch.
    var yearLookupAttempted: Bool = false

    /// The year to sort and group by: Discogs' year for this pressing, or
    /// else the album's year from elsewhere. Zero when neither is known.
    var shownYear: Int {
        year > 0 ? year : albumYear
    }

    init(
        releaseId: Int,
        instanceId: Int,
        title: String,
        artistDisplayName: String,
        year: Int,
        dateAdded: Date,
        masterId: Int? = nil,
        labelName: String? = nil,
        catalogNumber: String? = nil,
        genres: [String] = [],
        styles: [String] = [],
        discogsCoverURL: String,
        thumbURL: String,
        resolvedCoverURL: String? = nil,
        coverLookupAttempted: Bool = false,
        coverLookupFailures: Int = 0,
        coverRuleVersion: Int = 0
    ) {
        self.releaseId = releaseId
        self.instanceId = instanceId
        self.title = title
        self.artistDisplayName = artistDisplayName
        self.year = year
        self.dateAdded = dateAdded
        self.masterId = masterId
        self.labelName = labelName
        self.catalogNumber = catalogNumber
        self.genres = genres
        self.styles = styles
        self.discogsCoverURL = discogsCoverURL
        self.thumbURL = thumbURL
        self.resolvedCoverURL = resolvedCoverURL
        self.coverLookupAttempted = coverLookupAttempted
        self.coverLookupFailures = coverLookupFailures
        self.coverRuleVersion = coverRuleVersion
    }
}

extension CachedRelease {
    /// The cover URL to display: the resolved high-quality cover when
    /// available, otherwise the Discogs cover from the collection payload.
    var preferredCoverURL: URL? {
        URL(string: resolvedCoverURL ?? discogsCoverURL)
    }

    /// What VoiceOver reads for this record in the gallery, the same in both
    /// browse modes: a mosaic tile and CoverFlow's centred cover.
    var galleryAccessibilityLabel: String {
        String(localized: "\(artistDisplayName) – \(title)")
    }

    /// Builds a cached release from a Discogs collection entry. Callers are
    /// responsible for filtering to vinyl formats before persisting.
    convenience init(from release: CollectionRelease) {
        let info = release.basicInformation
        self.init(
            releaseId: release.id,
            instanceId: release.instanceId,
            title: info.title,
            artistDisplayName: info.artistDisplayName,
            year: info.year,
            dateAdded: Self.parseDate(release.dateAdded),
            masterId: info.masterId,
            labelName: info.primaryLabel?.name,
            catalogNumber: info.primaryLabel?.catno,
            genres: info.genres,
            styles: info.styles,
            discogsCoverURL: info.coverImage,
            thumbURL: info.thumb
        )
    }

    /// Refreshes the Discogs-sourced fields from a collection entry on
    /// re-sync, deliberately preserving `resolvedCoverURL`,
    /// `coverLookupAttempted`, `coverLookupFailures` and `coverRuleVersion`,
    /// which are owned by the cover-art pipeline, and `albumYear` and
    /// `yearLookupAttempted`, which are owned by `ReleaseYearService`.
    func apply(_ release: CollectionRelease) {
        let info = release.basicInformation
        instanceId = release.instanceId
        title = info.title
        artistDisplayName = info.artistDisplayName
        year = info.year
        dateAdded = Self.parseDate(release.dateAdded)
        masterId = info.masterId
        labelName = info.primaryLabel?.name
        catalogNumber = info.primaryLabel?.catno
        genres = info.genres
        styles = info.styles
        discogsCoverURL = info.coverImage
        thumbURL = info.thumb
    }

    // ISO8601DateFormatter is thread-safe for parsing, so a single shared
    // instance is fine despite not being Sendable.
    nonisolated(unsafe) private static let dateAddedFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ raw: String) -> Date {
        dateAddedFormatter.date(from: raw) ?? .distantPast
    }
}
