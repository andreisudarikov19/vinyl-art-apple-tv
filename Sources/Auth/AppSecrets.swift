import Foundation

/// Discogs API consumer credentials and shared HTTP identity.
///
/// Register your app at https://www.discogs.com/settings/developers to
/// obtain a consumer key and secret, then replace the placeholders below.
/// These values ship in the app binary and are not truly secret — they
/// identify the app to Discogs and rate-limit per-app.
enum AppSecrets {
    static let discogsConsumerKey = "YOUR_DISCOGS_CONSUMER_KEY"
    static let discogsConsumerSecret = "YOUR_DISCOGS_CONSUMER_SECRET"

    static let userAgent = "VinylForAppleTV/0.1 +https://github.com/andreisudarikov19/vinyl-art-apple-tv"

    static var hasDiscogsCredentials: Bool {
        discogsConsumerKey != "YOUR_DISCOGS_CONSUMER_KEY" &&
        discogsConsumerSecret != "YOUR_DISCOGS_CONSUMER_SECRET" &&
        !discogsConsumerKey.isEmpty &&
        !discogsConsumerSecret.isEmpty
    }
}
