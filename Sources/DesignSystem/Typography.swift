import AppKit
import CoreText
import SwiftUI

// Design-system text styles, in the current font set (View ▸ Font).
// Inter and IBM Plex Mono are embedded; if they fail to load, falls back to SF Pro / SF Mono.

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
    private static let hasInter = NSFont(name: "Inter", size: 13) != nil
    private static let hasPlexMono = NSFont(name: "IBMPlexMono-Regular", size: 13) != nil

    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if fonts == .inter, hasInter {
            return .custom("Inter", fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        let name = switch weight {
        case .light: "IBMPlexMono-Light"
        case .medium: "IBMPlexMono-Medium"
        default: "IBMPlexMono-Regular"
        }
        if fonts == .inter, hasPlexMono {
            return .custom(name, fixedSize: size).monospacedDigit()
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
}
