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
        let skin = Skin(id: "t", name: "T", appearance: .followsSystem, palette: [.ink: .init(light: 0x111111, dark: 0xEEEEEE)])
        #expect(hex(skin.color(.ink, for: light)) == 0x111111)
        #expect(hex(skin.color(.ink, for: dark)) == 0xEEEEEE)
    }

    @Test func alwaysDarkIgnoresLightAppearance() {
        let skin = Skin(id: "t", name: "T", appearance: .alwaysDark, palette: [.ink: .init(light: 0x111111, dark: 0xEEEEEE)])
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
}
