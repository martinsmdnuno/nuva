import AppKit
import Testing
@testable import NuVa

@MainActor
struct SkinTests {
    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!

    private func hex(_ color: NSColor) -> UInt32 {
        let c = color.usingColorSpace(.sRGB)!
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    @Test func nunoReadsTheAssetCatalog() {
        // ink: #1E2023 in Aluminium, #E8E6E1 in Lead (tokens.json).
        #expect(hex(Skin.nuno.color(.ink, for: light)) == 0x1E2023)
        #expect(hex(Skin.nuno.color(.ink, for: dark)) == 0xE8E6E1)
    }

    @Test func everyTokenHasAnAssetColour() {
        for token in ColorToken.allCases {
            #expect(NSColor(named: token.rawValue) != nil, "missing colour set \(token.rawValue)")
        }
    }

    @Test func paletteFollowsAppearance() {
        let skin = Skin(id: "t", name: "T", appearance: .followsSystem, fontSet: .inter, palette: [.ink: .init(light: 0x111111, dark: 0xEEEEEE)])
        #expect(hex(skin.color(.ink, for: light)) == 0x111111)
        #expect(hex(skin.color(.ink, for: dark)) == 0xEEEEEE)
    }

    @Test func alwaysDarkIgnoresLightAppearance() {
        let skin = Skin(id: "t", name: "T", appearance: .alwaysDark, fontSet: .inter, palette: [.ink: .init(light: 0x111111, dark: 0xEEEEEE)])
        #expect(hex(skin.color(.ink, for: light)) == 0xEEEEEE)
    }

    @Test func unknownSkinFallsBackToNuno() {
        #expect(Skin.with(id: "gone") == .nuno)
        #expect(Skin.with(id: nil) == .nuno)
    }

    @Test func storeIgnoresUnknownSavedSkin() {
        let defaults = UserDefaults(suiteName: "skin-tests")!
        defaults.removePersistentDomain(forName: "skin-tests")
        defaults.set("gone", forKey: "skin")
        #expect(SkinStore(defaults: defaults).current == .nuno)
    }

    @Test func fontSetFollowsSkinUntilChosen() {
        let defaults = UserDefaults(suiteName: "skin-tests-fonts")!
        defaults.removePersistentDomain(forName: "skin-tests-fonts")
        let store = SkinStore(defaults: defaults)
        #expect(store.fontChoice == nil)
        #expect(store.fontSet == Skin.nuno.fontSet)

        store.fontChoice = .system
        #expect(store.fontSet == .system)
        #expect(SkinStore.activeFonts.withLock { $0 } == .system)
        #expect(SkinStore(defaults: defaults).fontChoice == .system)

        store.fontChoice = nil
        #expect(defaults.string(forKey: "fontSet") == "skin")
        #expect(SkinStore(defaults: defaults).fontChoice == nil)
        #expect(SkinStore.activeFonts.withLock { $0 } == Skin.nuno.fontSet)
    }

    // MARK: Contrast (design system: every text pair 4.5:1; icons, LEDs and focus 3:1)

    private func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB)!
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private func ratio(_ skin: Skin, _ a: ColorToken, _ b: ColorToken, _ appearance: NSAppearance) -> Double {
        let la = luminance(skin.color(a, for: appearance)), lb = luminance(skin.color(b, for: appearance))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static let textPairs: [(ColorToken, ColorToken)] = [
        (.ink, .surface0), (.ink, .surface1), (.ink, .surface2),
        (.inkMuted, .surface0), (.inkMuted, .surface1), (.inkMuted, .surface2),
        (.signal, .surface0), (.signal, .surface2),
        (.displayInk, .display), (.displayMuted, .display),
        (.keyInk, .keyFace), (.keyInk, .keyPlay), (.keyModeInk, .keyMode),
        (.danger, .surface0), (.danger, .surface1),
    ]

    private static let graphicPairs: [(ColorToken, ColorToken)] = [
        (.focus, .surface0), (.led, .surface0), (.keyPlay, .surface0), (.keyFace, .surface0), (.fill, .track),
    ]

    @Test(arguments: Skin.all) func textPassesAA(skin: Skin) {
        if skin == .nuno {
            // The 1.0 palette misses a few pairs (docs/plans/skins-and-artwork.md, "Contrast gaps in Nuno").
            // Kept as is until decided; this fails once they are fixed, so the exception can go.
            withKnownIssue("Nuno 1.0 contrast gaps") { checkContrast(skin) }
        } else {
            checkContrast(skin)
        }
    }

    private func checkContrast(_ skin: Skin) {
        for appearance in [light, dark] {
            for (a, b) in Self.textPairs {
                let r = ratio(skin, a, b, appearance)
                #expect(r >= 4.5, "\(skin.id) \(appearance.name.rawValue): \(a.rawValue) on \(b.rawValue) is \(r)")
            }
            for (a, b) in Self.graphicPairs {
                let r = ratio(skin, a, b, appearance)
                #expect(r >= 3, "\(skin.id) \(appearance.name.rawValue): \(a.rawValue) on \(b.rawValue) is \(r)")
            }
        }
    }

    @Test func graphiteLayersAreDistinct() {
        for skin in [Skin.graphiteOrange, .graphiteGreen] {
            #expect(ratio(skin, .surface1, .surface0, dark) >= 1.2)
            #expect(ratio(skin, .surface2, .surface0, dark) >= 1.4)
            #expect(ratio(skin, .keyMode, .surface0, dark) >= 3)
        }
    }

    @Test func palettesCoverEveryToken() {
        for skin in Skin.all {
            guard let palette = skin.palette else { continue }
            #expect(Set(palette.keys) == Set(ColorToken.allCases), "\(skin.id)")
        }
    }

    @Test func graphiteIsAlwaysDarkWithOneAccent() {
        for skin in [Skin.graphiteOrange, .graphiteGreen] {
            #expect(skin.appearance == .alwaysDark)
            let accent = skin.palette![.keyPlay]!
            #expect(skin.palette![.led] == accent && skin.palette![.signal] == accent)
            // The accent stays in its three roles.
            let others = skin.palette!.filter { ![.keyPlay, .led, .signal].contains($0.key) }
            #expect(!others.values.contains(accent))
        }
    }
}

extension Skin: CustomTestStringConvertible {
    public var testDescription: String { id }
}
