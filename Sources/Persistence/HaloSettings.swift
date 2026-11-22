import Foundation

/// The three ambient-light switches in Settings. They replace the single
/// `UserPreferences.haloAutoEngage`.
///
/// - Gallery and track list: on or off. Where a switch is off, the remote
///   cannot turn the light on.
/// - Cover view: on, off, or manual, where Left and Right on the remote turn
///   the halo off and on and the last choice is remembered.
struct HaloSettings: Codable, Equatable, Sendable {
    enum Switch: String, Codable, CaseIterable, Sendable {
        case on, off
    }

    enum CoverMode: String, Codable, CaseIterable, Sendable {
        case on, off, manual
    }

    /// The tide behind the centre cover. Starts after a minute without a press.
    var gallery: Switch = .on
    /// The tide from the top left corner. Starts after 15 seconds without a press.
    var trackList: Switch = .off
    /// The lava-lamp halo.
    var coverView: CoverMode = .manual
    /// The last choice made with Left or Right in manual mode. Kept between launches.
    var manualCoverHaloOn = true

    init() {}

    /// Whether the cover view should show its halo right now.
    var coverHaloIsOn: Bool {
        switch coverView {
        case .on: true
        case .off: false
        case .manual: manualCoverHaloOn
        }
    }

    /// The Select action on a Settings row: the next choice in order.
    mutating func cycleCoverView() {
        let all = CoverMode.allCases
        coverView = all[((all.firstIndex(of: coverView) ?? 0) + 1) % all.count]
    }

    /// Settings for someone upgrading. `haloAutoEngage == false` meant
    /// "manual": no halo in the Gallery and a pill in the cover view.
    static func migrated(fromAutoEngage autoEngage: Bool) -> HaloSettings {
        var settings = HaloSettings()
        if !autoEngage {
            settings.gallery = .off
            settings.manualCoverHaloOn = false
        }
        return settings
    }
}
