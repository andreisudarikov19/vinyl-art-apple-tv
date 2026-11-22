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
/// label's own yolk pill is the only focus cue the notice should show.
struct DiscogsNoticeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// The notice's label (spec 04): a QR icon and the text, quiet at rest. In
/// focus it is a yolk pill 58 pt high, like every other control in focus.
/// The pill's room is kept at rest too, so nothing moves when focus arrives.
struct DiscogsNoticeLabel: View {
    @Environment(\.isFocused) private var isFocused

    /// The room at each side of the pill. The record screen pulls the label
    /// back by this much, so the icon lines up with the table's left edge.
    static let sidePadding: CGFloat = 24
    static let height: CGFloat = 58

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(DiscogsNotice.text)
                .font(Theme.sans(Theme.Size.small, isFocused ? .semibold : .regular))
        }
        .foregroundStyle(isFocused ? Theme.onYolk : Theme.quiet)
        .padding(.horizontal, Self.sidePadding)
        .frame(height: Self.height)
        .background {
            if isFocused {
                Capsule().fill(Theme.yolk)
            }
        }
    }
}

/// The panel that takes the track list's place when the Discogs line is
/// chosen (spec 04, reference/RecordDiscogsQR.jpg): a QR code for this
/// release's page on discogs.com, the attribution at full size, the
/// non-affiliation notice, and the address in type for anyone who cannot
/// scan. Nothing on it takes focus; Menu closes it.
struct DiscogsReleasePanel: View {
    let releaseId: Int

    private var address: String { DiscogsNotice.releasePageURL(releaseId: releaseId) }

    /// The panel's inner margin, and the QR code's side.
    private let margin: CGFloat = 64
    private let codeSide: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: margin) {
                code
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCAN WITH YOUR PHONE")
                        .font(Theme.mono(Theme.Size.small, medium: true))
                        .tracking(Theme.Size.small * Theme.eyebrowTracking)
                        .foregroundStyle(Theme.yolk)
                    Text("This record on Discogs")
                        .font(Theme.serif(Theme.Size.cardTitle))
                        .tracking(-Theme.Size.cardTitle * 0.02)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                    Text("The code opens the Discogs page for this exact release, with its full credits, notes and pictures.")
                        .font(Theme.sans(Theme.Size.control))
                        .foregroundStyle(Theme.body)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                }
            }
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .padding(.top, margin)
            Text(DiscogsNotice.text)
                .font(Theme.sans(Theme.Size.control, .medium))
                .foregroundStyle(Theme.text)
                .padding(.top, 40)
            Text(AboutView.discogsNotice)
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Or type this into a browser")
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .padding(.top, 28)
            Text(verbatim: address)
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.text)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    /// The code, black on white with 16 pt corners. If it cannot be drawn,
    /// its square stays empty: the address is in type below.
    @ViewBuilder
    private var code: some View {
        if let qr = QRCode.image(from: address) {
            Image(uiImage: qr)
                .interpolation(.none)
                .resizable()
                .frame(width: codeSide, height: codeSide)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("QR code for this release on discogs.com")
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.line)
                .frame(width: codeSide, height: codeSide)
        }
    }
}
