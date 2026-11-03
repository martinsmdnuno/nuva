import AppKit
import Testing
@testable import NuVa

struct ArtworkGlowTests {
    private func image(_ fill: NSColor, accent: NSColor? = nil) -> NSImage {
        NSImage(size: NSSize(width: 60, height: 60), flipped: false) { rect in
            fill.setFill()
            rect.fill()
            if let accent {
                accent.setFill()
                NSRect(x: 0, y: 0, width: 60, height: 15).fill()
            }
            return true
        }
    }

    @Test func coverInGreysHasNoGlow() {
        #expect(ArtworkGlow.tint(of: image(NSColor(white: 0.5, alpha: 1))) == nil)
    }

    @Test func glowTakesTheCoversMainHue() throws {
        // Mostly orange, with a strip of blue: orange wins, not a muddy average of the two.
        let orange = NSColor(srgbRed: 0.85, green: 0.45, blue: 0.1, alpha: 1)
        let blue = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1)
        let tint = try #require(ArtworkGlow.tint(of: image(orange, accent: blue)))
        #expect(abs(tint.hue - Double(orange.hueComponent)) < 0.03)
    }

    @Test func glowKeepsMutedTextReadable() throws {
        let tint = ArtworkGlow.Tint(hue: 0.02, saturation: 0.9)
        let muted = NSColor(srgbRed: 0x8E / 255, green: 0x8C / 255, blue: 0x87 / 255, alpha: 1)
        let ceiling = ArtworkGlow.ceiling(for: muted)
        let glow = ArtworkGlow.color(tint, luminance: ceiling)
        let contrast = (ArtworkGlow.luminance(muted) + 0.05) / (ArtworkGlow.luminance(glow) + 0.05)
        #expect(contrast >= 4.5)
        // As bright as that allows, so it shows.
        #expect(ArtworkGlow.luminance(glow) > ceiling * 0.95)
    }
}
