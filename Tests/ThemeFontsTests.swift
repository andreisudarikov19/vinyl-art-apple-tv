import Testing
import UIKit
@testable import VinylForAppleTV

struct ThemeFontsTests {
    /// The six fixed-weight cuts the design needs, by PostScript name (spec 00).
    /// Theme.swift asks for these names; a mismatch would fall back silently.
    @Test func findsAllSixFontsByPostScriptName() {
        let names = [
            "Fraunces72pt-Regular",
            "Inter28pt-Regular",
            "Inter28pt-Medium",
            "Inter28pt-SemiBold",
            "DMMono-Regular",
            "DMMono-Medium",
        ]
        for name in names {
            let font = UIFont(name: name, size: 29)
            #expect(font != nil, "\(name) is not registered with the app")
            #expect(font?.fontName == name, "\(name) does not match its PostScript name")
        }
    }
}
