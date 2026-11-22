import SwiftUI

/// The About screen, opened from Settings and laid out like it
/// (design-handoff/specs/03-settings.md): the app, its version and the
/// Discogs notice on the left; a card of QR codes on the right. tvOS has no
/// browser, so the codes are for a phone, and the two addresses under them
/// are plain text to type. Nothing on the screen takes focus; Menu on the
/// remote closes it.
struct AboutView: View {
    /// Discogs' API Terms of Use require this notice, word for word.
    static let discogsNotice = "This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC."

    private let columnTop: CGFloat = 96
    private let columnWidth: CGFloat = 720
    private let cardTop: CGFloat = 120
    private let cardSize = CGSize(width: 940, height: 840)
    private let cardPadding: CGFloat = 64

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsBackground()
            HStack(alignment: .top, spacing: 0) {
                app
                    .frame(width: columnWidth, alignment: .topLeading)
                    .padding(.top, columnTop)
                Spacer(minLength: 0)
                card
                    .frame(width: cardSize.width, height: cardSize.height)
                    .padding(.top, cardTop)
            }
            .padding(.horizontal, Theme.safeSide)
        }
        .ignoresSafeArea()
    }

    // MARK: - The app

    private var app: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT")
                .font(Theme.mono(Theme.Size.small, medium: true))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.yolk)
            Text("Vinyl for Apple TV")
                .font(Theme.serif(Theme.Size.screenTitle))
                .tracking(-Theme.Size.screenTitle * 0.02)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(AppVersion.current.uppercased())
                .font(Theme.mono(Theme.Size.small))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.body)
                .padding(.top, 20)
            Text(Self.discogsNotice)
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 48)
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCAN WITH YOUR PHONE")
                .font(Theme.mono(Theme.Size.small, medium: true))
                .tracking(Theme.Size.small * Theme.eyebrowTracking)
                .foregroundStyle(Theme.yolk)
            HStack(alignment: .top, spacing: 0) {
                AboutCode(title: "Privacy policy", address: AppAddresses.privacyPolicy)
                Spacer(minLength: 0)
                AboutCode(title: "Support", address: AppAddresses.support)
                Spacer(minLength: 0)
                AboutCode(title: "Email us", address: "mailto:" + AppAddresses.supportEmail)
            }
            .padding(.top, 40)
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .padding(.top, 56)
            Text("Or type one of these into a browser:")
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .padding(.top, 40)
            AboutAddress(title: "Website", value: Self.typed(AppAddresses.site))
                .padding(.top, 24)
            AboutAddress(title: "Email", value: AppAddresses.supportEmail)
                .padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// An address as someone would type it: without "https://" and without
    /// the slash at the end.
    static func typed(_ address: String) -> String {
        var typed = address
        if typed.hasPrefix("https://") { typed.removeFirst("https://".count) }
        if typed.hasSuffix("/") { typed.removeLast() }
        return typed
    }
}

/// A QR code, 240 pt square, in ink on the app's off-white, with what it
/// opens under it.
private struct AboutCode: View {
    let title: LocalizedStringKey
    let address: String

    private let side: CGFloat = 240

    var body: some View {
        VStack(spacing: 20) {
            code
            Text(title)
                .font(Theme.sans(Theme.Size.control, .medium))
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var code: some View {
        if let qr = QRCode.image(from: address) {
            Image(uiImage: qr)
                .interpolation(.none)
                .resizable()
                // White becomes the off-white ground; black stays ink.
                .colorMultiply(Theme.text)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("QR code")
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.line)
                .frame(width: side, height: side)
        }
    }
}

/// A quiet label in front of the address it names. VoiceOver reads the pair
/// as one element.
private struct AboutAddress: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .font(Theme.sans(Theme.Size.small))
                .foregroundStyle(Theme.quiet)
                .frame(width: 140, alignment: .leading)
            Text(verbatim: value)
                .font(Theme.mono(Theme.Size.small))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutView()
}
