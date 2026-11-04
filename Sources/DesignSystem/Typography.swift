import AppKit
import CoreText
import SwiftUI

// Design-system text styles, in the current font set (View ▸ Font).
// The sets' fonts are embedded; any that fails to load falls back to SF Pro / SF Mono.

enum Typography {
    /// Registers the fonts embedded in the bundle. Call once at launch.
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static var fonts: FontSet { SkinStore.activeFonts.withLock { $0 } }

    // Checked once (after registerFonts), not on every redraw now that styles are computed.
    private static let families: Set<String> = Set(FontSet.allCases.compactMap(\.sans).filter {
        NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil
    })
    private static let faces: Set<String> = Set(FontSet.allCases.flatMap { set in
        [Font.Weight.light, .regular, .medium].compactMap { set.mono($0) }
    }.filter { NSFont(name: $0, size: 13) != nil })

    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let family = fonts.sans, families.contains(family) {
            return .custom(family, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let face = fonts.mono(weight), faces.contains(face) {
            return .custom(face, fixedSize: size).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

extension Font {
    static var dsDisplayTime: Font { Typography.mono(28, .light) }
    static var dsDisplayTimeMini: Font { Typography.mono(17, .regular) }
    static var dsDisplayMeta: Font { Typography.mono(11, .regular) }
    static var dsTitle: Font { Typography.sans(15, .medium) }
    static var dsBody: Font { Typography.sans(13, .regular) }
    static var dsLabel: Font { Typography.sans(11, .medium) }
    static var dsCaption: Font { Typography.sans(11, .regular) }
    /// Legend printed on the chassis, always lowercase.
    static var dsLegend: Font { Typography.sans(10, .regular) }
    static var dsDuration: Font { Typography.mono(12, .regular) }
    /// Numbers printed on a scale (volume).
    static var dsScale: Font { Typography.mono(9, .regular) }
    /// Shortcuts and details beside a label.
    static var dsHint: Font { Typography.mono(10, .regular) }
    /// The title of a document window (Terms and Privacy).
    static var dsDocumentTitle: Font { Typography.sans(20, .semibold) }
    /// An SF Symbol beside text or on a key. Symbols live in the system font, whatever the font set.
    static func dsIcon(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }

    // Ambient mode: the display's styles at the scale of the screen (sizes from 1% of its width).
    static func dsAmbientTime(_ size: CGFloat) -> Font { Typography.mono(size, .light) }
    static func dsAmbientMeta(_ size: CGFloat) -> Font { Typography.mono(size, .regular) }
    static func dsAmbientTitle(_ size: CGFloat) -> Font { Typography.sans(size, .medium) }
    static func dsAmbientCaption(_ size: CGFloat) -> Font { Typography.sans(size, .regular) }
}
