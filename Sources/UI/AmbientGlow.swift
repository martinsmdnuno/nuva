import AppKit
import SwiftUI

/// Ambient mode's glow from the album cover: the cover's telling hue as a soft light behind the
/// face, darkened until the display's muted text keeps 4.5:1 on it. Only with artwork on.
enum ArtworkGlow {
    /// Hue and saturation of the cover's main colour (0 to 1 each).
    struct Tint: Equatable {
        let hue: Double
        let saturation: Double
    }

    /// The hue the cover's vivid pixels share most, or nil for a cover in greys.
    static func tint(of image: NSImage) -> Tint? {
        let side = 24
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        // Hue histogram in 36 bins, weighted so vivid, lit pixels count and greys and shadows don't.
        let count = 36
        var weights = Array(repeating: 0.0, count: count)
        var saturations = Array(repeating: 0.0, count: count)
        var hues = Array(repeating: SIMD2<Double>(0, 0), count: count)
        for y in 0..<side {
            for x in 0..<side {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                let w = Double(s * s * b * a)
                let bin = min(Int(h * CGFloat(count)), count - 1)
                weights[bin] += w
                saturations[bin] += Double(s) * w
                hues[bin] += SIMD2(cos(2 * .pi * Double(h)), sin(2 * .pi * Double(h))) * w
            }
        }
        // The strongest bin and its neighbours: a hue the cover is made of, not an average of all.
        guard let peak = weights.indices.max(by: { weights[$0] < weights[$1] }),
              weights[peak] / Double(side * side) > 0.01
        else { return nil }
        let near = [(peak + count - 1) % count, peak, (peak + 1) % count]
        let weight = near.map { weights[$0] }.reduce(0, +)
        let direction = near.map { hues[$0] }.reduce(.zero, +)
        let hue = atan2(direction.y, direction.x) / (2 * .pi)
        return Tint(hue: hue < 0 ? hue + 1 : hue, saturation: near.map { saturations[$0] }.reduce(0, +) / weight)
    }

    /// The tint as a colour whose relative luminance is at most `ceiling`, as bright as that allows.
    static func color(_ tint: Tint, luminance ceiling: Double) -> NSColor {
        let saturation = min(max(tint.saturation, 0.45), 0.8)
        func make(_ brightness: Double) -> NSColor {
            NSColor(colorSpace: .sRGB, hue: tint.hue, saturation: saturation, brightness: brightness, alpha: 1)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if luminance(make(middle)) > ceiling { high = middle } else { low = middle }
        }
        return make(low)
    }

    /// Highest relative luminance a background can have for `text` to keep 4.5:1 on it.
    static func ceiling(for text: NSColor) -> Double {
        (luminance(text) + 0.05) / 4.5 - 0.05
    }

    /// WCAG relative luminance of an sRGB colour.
    static func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    /// The glow for `image` in the current skin's dark display, or nil when there is none to show
    /// (a cover in greys, or a display with no room above its own colour).
    @MainActor static func color(for image: NSImage) -> Color? {
        let tint: Tint?
        if let last, last.image === image {
            tint = last.tint
        } else {
            tint = Self.tint(of: image)
            last = (image, tint)
        }
        guard let tint, let dark = NSAppearance(named: .darkAqua) else { return nil }
        let skin = SkinStore.active.withLock { $0 }
        let ceiling = Self.ceiling(for: skin.color(.displayMuted, for: dark))
        guard ceiling > luminance(skin.color(.display, for: dark)) + 0.002 else { return nil }
        return Color(nsColor: color(tint, luminance: ceiling))
    }

    /// The last cover measured: the ambient view asks every second.
    @MainActor private static var last: (image: NSImage, tint: Tint?)?
}

/// The cover's glow behind the ambient faces: brightest a little above the middle, fading into the
/// display's colour towards the edges.
struct AmbientGlow: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            RadialGradient(
                colors: [color, color.opacity(0)], center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0, endRadius: max(geometry.size.width, geometry.size.height) * 0.7)
        }
        .allowsHitTesting(false)
    }
}
