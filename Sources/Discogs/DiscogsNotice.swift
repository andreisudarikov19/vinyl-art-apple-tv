import SwiftUI

/// The attribution line the Discogs API terms require beside any Discogs data.
enum DiscogsNotice {
    static let text = "Data provided by Discogs"

    /// The release's page on discogs.com, not the api.discogs.com resource,
    /// so a phone that scans it lands on the release.
    static func releasePageURL(releaseId: Int) -> String {
        "https://www.discogs.com/release/\(releaseId)"
    }
}

/// Renders only the notice's label. tvOS draws a focus platter behind a
/// `.plain` button, which would frame the label in a large white block; the
/// label's own glass pill is the only focus cue the notice should show.
struct DiscogsNoticeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// The notice's label, in the tag family: a QR glyph and the text, in the
/// tag pill's shape and padding. At rest it is quiet with no fill; when the
/// remote focuses it, the tag pill's glass appears, so it reveals itself as
/// selectable like the pills beside it.
struct DiscogsNoticeLabel: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 16, weight: .medium))
                .accessibilityHidden(true)
            Text(DiscogsNotice.text)
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.white.opacity(isFocused ? 0.88 : 0.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            if isFocused {
                TagPillGlass()
            }
        }
    }
}

/// Frosted glass for the catalog tag pills and the focused Discogs notice: an
/// ultra-thin material for the blurred translucency behind the text, plus a
/// thin white stroke for the edge highlight that sells the "glass" reading at
/// TV viewing distance. No tvOS 26 dependency — `.ultraThinMaterial` is
/// available on every supported version.
struct TagPillGlass: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            )
    }
}

/// Full-screen QR code of a release's discogs.com page, opened from the
/// Discogs notice. Nothing on it is focusable; the remote's Menu button closes it.
struct DiscogsReleaseQRView: View {
    let url: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                if let qr = QRCode.image(from: url) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 360, height: 360)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Text(url)
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                Text("Scan with your phone")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
