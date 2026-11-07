import Foundation

/// The app's version and build as the Settings menu and the About screen show
/// them, e.g. "Version 0.18.2 (24)". The support page asks people to quote it.
enum AppVersion {
    /// Built once from the app's own bundle.
    static let current = string(infoDictionary: Bundle.main.infoDictionary)

    /// Leaves out a missing build, and says "unknown" for a missing version
    /// rather than showing an empty one.
    static func string(infoDictionary: [String: Any]?) -> String {
        let version = value(for: "CFBundleShortVersionString", in: infoDictionary) ?? "unknown"
        guard let build = value(for: "CFBundleVersion", in: infoDictionary) else {
            return "Version \(version)"
        }
        return "Version \(version) (\(build))"
    }

    private static func value(for key: String, in infoDictionary: [String: Any]?) -> String? {
        guard let value = infoDictionary?[key] as? String, !value.isEmpty else { return nil }
        return value
    }
}
