import AppKit
import CoreText
import SwiftUI

// Estilos de letra do design system. Inter e IBM Plex Mono vêm embebidas;
// se não carregarem, cai para SF Pro / SF Mono.

enum Typography {
    /// Regista as fontes embebidas no bundle. Chamar uma vez no arranque.
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if NSFont(name: "Inter", size: size) != nil {
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
        if NSFont(name: name, size: size) != nil {
            return .custom(name, fixedSize: size).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

extension Font {
    static let dsDisplayTime = Typography.mono(28, .light)
    static let dsDisplayTimeMini = Typography.mono(17, .regular)
    static let dsDisplayMeta = Typography.mono(11, .regular)
    static let dsTitle = Typography.sans(15, .medium)
    static let dsBody = Typography.sans(13, .regular)
    static let dsLabel = Typography.sans(11, .medium)
    static let dsCaption = Typography.sans(11, .regular)
    /// Legenda impressa no chassis, sempre em minúsculas.
    static let dsLegend = Typography.sans(10, .regular)
    static let dsDuration = Typography.mono(12, .regular)
}
