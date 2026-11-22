import SwiftUI

/// The app's colours, type and shared measures. They are the website's design
/// system (docs/styles.css), so the app and the site read as one product.
///
/// Fonts: the six files in Sources/DesignSystem/Fonts are bundled and listed in
/// UIAppFonts (project.yml). The names below are the files' PostScript names.
enum Theme {
    // MARK: Colour

    /// The ground of every screen.
    static let ink = Color(hex: 0x0B0A08)
    /// Cards, menus, resting pills.
    static let surface = Color(hex: 0x14110D)
    /// Titles and primary text.
    static let text = Color(hex: 0xFAF7F2)
    /// Body text and resting toolbar items.
    static let body = Color(hex: 0xC9C3B8)
    /// Labels, counts, credits.
    static let quiet = Color(hex: 0xA39C90)
    /// Focus, the scale's needle, an active filter. Nothing else.
    static let yolk = Color(hex: 0xF4C444)
    /// Text and icons on a yolk fill.
    static let onYolk = Color(hex: 0x14110B)
    /// The destructive choice in the sign-out dialog.
    static let danger = Color(hex: 0xFF9C8A)

    /// Hairlines and outlines, as white at this opacity.
    static let line = Color(hex: 0xFAF7F2).opacity(0.12)
    static let lineStrong = Color(hex: 0xFAF7F2).opacity(0.22)

    /// A style within a "Genre: style" pair, and any second-rank value: the
    /// same colour as its neighbour at this opacity.
    static let secondaryOpacity = 0.65

    // MARK: Type

    /// Fraunces, for album titles and screen headings.
    static func serif(_ size: CGFloat) -> Font {
        .custom("Fraunces72pt-Regular", fixedSize: size)
    }

    enum SansWeight { case regular, medium, semibold }

    /// Inter, for everything read as text.
    static func sans(_ size: CGFloat, _ weight: SansWeight = .regular) -> Font {
        switch weight {
        case .regular: .custom("Inter28pt-Regular", fixedSize: size)
        case .medium: .custom("Inter28pt-Medium", fixedSize: size)
        case .semibold: .custom("Inter28pt-SemiBold", fixedSize: size)
        }
    }

    /// DM Mono, for labels, numbers, years and durations.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "DMMono-Medium" : "DMMono-Regular", fixedSize: size)
    }

    /// Named sizes used across the screens. Nothing in the app is set under 25 pt.
    enum Size {
        static let screenTitle: CGFloat = 76   // Fraunces: "Settings"
        static let albumTitle: CGFloat = 52    // Fraunces, line height 56
        static let cardTitle: CGFloat = 48     // Fraunces
        static let reading: CGFloat = 36       // DM Mono Medium: the scale's reading
        static let control: CGFloat = 29       // Inter: toolbar, rows, track titles
        static let small: CGFloat = 25         // Inter and DM Mono: labels, credits, counts
    }

    /// Tracking for uppercase DM Mono eyebrows ("SETTINGS", "SIDE F"), in em.
    static let eyebrowTracking: CGFloat = 0.16

    // MARK: Measure

    /// tvOS safe area: keep everything that matters inside it.
    static let safeSide: CGFloat = 80
    static let safeTopBottom: CGFloat = 60

    /// A toolbar control or menu row.
    static let controlHeight: CGFloat = 66
    /// A Settings row.
    static let rowHeight: CGFloat = 84
    static let controlPadding: CGFloat = 28
    static let controlGap: CGFloat = 12
    static let cardRadius: CGFloat = 28
}

extension Color {
    /// 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
