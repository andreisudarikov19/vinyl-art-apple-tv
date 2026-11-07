import SwiftUI

/// Full-screen About page, opened from the Settings menu. tvOS has no
/// browser, so the addresses are plain text to type on a phone or computer.
/// Nothing on it is focusable; the remote's Menu button closes it.
struct AboutView: View {
    /// Discogs' API Terms of Use require this notice, word for word.
    static let discogsNotice = "This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC."

    /// The site's yolk yellow (docs/styles.css), as a faint glow so the page
    /// stays calm behind the text.
    private static let glow = Color(red: 1, green: 0.757, blue: 0.027).opacity(0.22)

    var body: some View {
        ZStack {
            CollectionGlowBackground(glowColor: Self.glow, reference: 700)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 60)
                addresses
                Spacer(minLength: 60)
                Text(Self.discogsNotice)
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    // Narrow enough that the line breaks between the notice's
                    // two sentences rather than in the middle of the second.
                    .frame(maxWidth: 1180)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 110)
            .padding(.horizontal, 80)
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Text("Vinyl for Apple TV")
                .font(.system(size: 80, weight: .light, design: .serif))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(AppVersion.current)
                .font(.system(size: 31))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
    }

    private var addresses: some View {
        VStack(spacing: 44) {
            AddressRow(title: "Privacy policy", value: AppAddresses.privacyPolicy)
            AddressRow(title: "Support", value: AppAddresses.support)
            AddressRow(title: "Email", value: AppAddresses.supportEmail)
        }
    }
}

/// A caption above the address it names. VoiceOver reads the pair as one
/// element, e.g. "Support, https://…".
private struct AddressRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AboutView()
}
