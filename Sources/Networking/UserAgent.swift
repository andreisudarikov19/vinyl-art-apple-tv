import Foundation

/// The User-Agent sent to Discogs, MusicBrainz and the Cover Art Archive.
/// MusicBrainz asks for `Application/version ( contact )` and may throttle
/// clients without one; Discogs asks for a unique, descriptive one.
enum UserAgent {
    /// Built once from the app's own marketing version.
    static let app = string(infoDictionary: Bundle.main.infoDictionary)

    /// Leaves the version out, rather than sending an empty one, when the
    /// bundle has no `CFBundleShortVersionString`.
    static func string(infoDictionary: [String: Any]?) -> String {
        let contact = AppAddresses.support
        if let version = infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
            return "VinylForAppleTV/\(version) ( \(contact) )"
        }
        return "VinylForAppleTV ( \(contact) )"
    }
}
