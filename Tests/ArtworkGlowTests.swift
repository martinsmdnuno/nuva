import AppKit
import Testing
@testable import NuVa

struct ArtworkGlowTests {
    private let display = NSColor(srgbRed: 0x14 / 255, green: 0x15 / 255, blue: 0x17 / 255, alpha: 1)
    private let muted = NSColor(srgbRed: 0x8E / 255, green: 0x8C / 255, blue: 0x87 / 255, alpha: 1)

    /// Top half orange, bottom half blue.
    private func cover() -> NSImage {
        NSImage(size: NSSize(width: 60, height: 60), flipped: false) { rect in
            NSColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1).setFill()
            rect.fill()
            NSColor(srgbRed: 0.85, green: 0.45, blue: 0.1, alpha: 1).setFill()
            NSRect(x: 0, y: 30, width: 60, height: 30).fill()
            return true
        }
    }

    @Test func cellsKeepTheCoversLayout() {
        let cells = ArtworkGlow.cells(of: cover())
        #expect(cells.count == 16)
        // Row by row from the top: orange first, blue last.
        #expect(cells[0].redComponent > cells[0].blueComponent)
        #expect(cells[15].blueComponent > cells[15].redComponent)
    }

    @Test func shadeKeepsMutedTextReadable() {
        let ceiling = ArtworkGlow.ceiling(for: muted)
        let shaded = ArtworkGlow.shade(NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1), relative: 1, ceiling: ceiling)
        let contrast = (ArtworkGlow.luminance(muted) + 0.05) / (ArtworkGlow.luminance(shaded) + 0.05)
        #expect(contrast >= 4.5)
        #expect(ArtworkGlow.luminance(shaded) > ceiling * 0.95)
    }

    @Test func fieldNeverPassesTheContrastCeiling() throws {
        let ceiling = ArtworkGlow.ceiling(for: muted)
        let field = try #require(ArtworkGlow.field(of: cover(), ceiling: ceiling, display: display))
        #expect(field.width == 640 && field.height == 400)
        let rep = NSBitmapImageRep(cgImage: field)
        var brightest = 0.0
        for y in stride(from: 0, to: field.height, by: 7) {
            for x in stride(from: 0, to: field.width, by: 7) {
                // The image is sRGB; the rep reports its pixels in another space, so read the values as sRGB.
                let c = rep.colorAt(x: x, y: y)!
                let pixel = NSColor(srgbRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: 1)
                brightest = max(brightest, ArtworkGlow.luminance(pixel))
            }
        }
        #expect((ArtworkGlow.luminance(muted) + 0.05) / (brightest + 0.05) >= 4.5)
        // And it shows: well above the display's own colour somewhere.
        #expect(brightest > ArtworkGlow.luminance(display) * 1.5)
    }

    @Test func aCoverInGreysStillGlows() throws {
        let grey = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            NSColor(white: 0.6, alpha: 1).setFill()
            rect.fill()
            return true
        }
        #expect(ArtworkGlow.field(of: grey, ceiling: ArtworkGlow.ceiling(for: muted), display: display) != nil)
    }

    @Test func pulseSwellsFastAndSettlesSlowly() {
        let pulse = GlowPulse()
        let start = Date()
        let loud: [Float] = [-12, -12, -12]
        var level = 0.0
        for frame in 1...12 { level = pulse.update(at: start.addingTimeInterval(Double(frame) / 120), bands: loud) }
        #expect(level > 0.8)  // 100 ms of a loud kick: nearly full
        for frame in 13...24 { level = pulse.update(at: start.addingTimeInterval(Double(frame) / 120), bands: nil) }
        #expect(level > 0.6)  // 100 ms of silence: still glowing
    }

    /// Without a cover the field is made of the skin's own lights, under the same contrast ceiling.
    @Test func skinLightsMakeAFieldUnderTheCeiling() throws {
        let display = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        let muted = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.62, alpha: 1)
        let ceiling = ArtworkGlow.ceiling(for: muted)
        let lights = [0xFF2BD6, 0x00E5FF, 0xB6FF3B].map { hex in
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let field = try #require(ArtworkGlow.field(lights: lights, ceiling: ceiling, display: display))
        let rep = NSBitmapImageRep(cgImage: field)
        var brightest = 0.0
        var hues: Set<Int> = []
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                // The image is sRGB; the rep reports its pixels in another space, so read the values as sRGB.
                guard let raw = rep.colorAt(x: x, y: y) else { continue }
                let c = NSColor(srgbRed: raw.redComponent, green: raw.greenComponent, blue: raw.blueComponent, alpha: 1)
                brightest = max(brightest, ArtworkGlow.luminance(c))
                if c.saturationComponent > 0.3 { hues.insert(Int(c.hueComponent * 6)) }
            }
        }
        #expect((ArtworkGlow.luminance(muted) + 0.05) / (brightest + 0.05) >= 4.5)
        #expect(brightest > ArtworkGlow.luminance(display))
        // More than one of the lights shows.
        #expect(hues.count >= 2)
        // One colour alone (a skin with only its LED) still makes a field.
        #expect(ArtworkGlow.field(lights: [lights[0]], ceiling: ceiling, display: display) != nil)
        #expect(ArtworkGlow.field(lights: [], ceiling: ceiling, display: display) == nil)
    }
}
