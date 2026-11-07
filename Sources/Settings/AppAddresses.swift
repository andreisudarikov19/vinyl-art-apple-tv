import Foundation

/// The app's public addresses: the pages GitHub Pages publishes from `docs/`
/// and the support inbox. The About screen shows them and the User-Agent
/// names the support page, so they live here once.
enum AppAddresses {
    static let site = "https://andreisudarikov19.github.io/vinyl-art-apple-tv/"
    static let privacyPolicy = site + "privacy.html"
    static let support = site + "support.html"
    static let supportEmail = "support.vinyl.for.appletv@gmail.com"
}
