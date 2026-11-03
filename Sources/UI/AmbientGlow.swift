import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Ambient mode's glow from the album cover: the cover reduced to a 4×4 grid of its own colours,
/// each darkened until the display's muted text keeps 4.5:1 on it, then blurred into a soft field
/// that keeps the cover's layout (a warm top, a blue corner…). Only with artwork on.
enum ArtworkGlow {
    /// The field for one cover, rendered once; equal when it comes from the same cover.
    struct Field: Equatable {
        let image: CGImage
        let id: ObjectIdentifier

        static func == (a: Field, b: Field) -> Bool { a.id == b.id }
    }

    static let grid = 4
    /// The field's size: small, since it is all blur, and 16:10 like most screens.
    static let size = CGSize(width: 640, height: 400)

    /// The cover's average colour in each cell of a `grid`×`grid` grid, row by row from the top.
    static func cells(of image: NSImage) -> [NSColor] {
        // Drawn at 4× the grid, then each cell averaged, so a cell is its area's colour.
        let side = grid * 4
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var cells: [NSColor] = []
        for row in 0..<grid {
            for column in 0..<grid {
                var sum = SIMD3<Double>(0, 0, 0)
                for y in row * 4 ..< row * 4 + 4 {
                    for x in column * 4 ..< column * 4 + 4 {
                        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        sum += SIMD3(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
                    }
                }
                let mean = sum / 16
                cells.append(NSColor(srgbRed: mean.x, green: mean.y, blue: mean.z, alpha: 1))
            }
        }
        return cells
    }

    /// `color` with its hue, a little more saturated, at a luminance from 40% of `ceiling` (the
    /// cover's darkest parts) to all of it (its brightest, `relative` 1).
    static func shade(_ color: NSColor, relative: Double, ceiling: Double) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let saturation = min(0.9, Double(s) * 1.15)
        let target = ceiling * (0.4 + 0.6 * min(max(relative, 0), 1))
        func make(_ brightness: Double) -> NSColor {
            NSColor(colorSpace: .sRGB, hue: h, saturation: saturation, brightness: brightness, alpha: 1)
        }
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if luminance(make(middle)) > target { high = middle } else { low = middle }
        }
        return make(low)
    }

    /// The blurred field for `image`, never brighter than `ceiling`, darkened towards `display` at
    /// the edges and dithered so a big screen shows no bands in its dark gradients.
    static func field(of image: NSImage, ceiling: Double, display: NSColor) -> CGImage? {
        let colors = cells(of: image)
        guard colors.count == grid * grid else { return nil }
        let brightest = colors.map(luminance).max() ?? 0
        // A little under the ceiling, for the dither's half step.
        let safe = ceiling * 0.95
        let shaded = colors.map { shade($0, relative: brightest > 0 ? luminance($0) / brightest : 0, ceiling: safe) }

        var bytes = [UInt8]()
        for color in shaded {
            let c = color.usingColorSpace(.sRGB) ?? color
            bytes += [c.redComponent, c.greenComponent, c.blueComponent].map { UInt8(($0 * 255).rounded()) } + [255]
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let grid = CGImage(
                width: grid, height: grid, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: grid * 4, space: sRGB,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }

        let rect = CGRect(origin: .zero, size: size)
        let cellsImage = CIImage(cgImage: grid)
        let stretched = cellsImage.clampedToExtent().samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: size.width / CGFloat(Self.grid), y: size.height / CGFloat(Self.grid)))
            .applyingGaussianBlur(sigma: size.width / 14)
            .cropped(to: rect)

        // Edges fall back towards the display's own colour.
        let edge = CIColor(color: display.withAlphaComponent(0.55)) ?? CIColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        let vignette = CIFilter.radialGradient()
        vignette.center = CGPoint(x: size.width / 2, y: size.height / 2)
        vignette.radius0 = Float(size.height * 0.35)
        vignette.radius1 = Float(size.width * 0.62)
        vignette.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        vignette.color1 = edge
        let lit = (vignette.outputImage?.cropped(to: rect)).map { $0.composited(over: stretched) } ?? stretched

        // Grey noise of about ±0.6 of an 8-bit step, added in the encoded values.
        let noise = CIFilter.randomGenerator().outputImage?
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.2 / 255, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1.2 / 255, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1.2 / 255, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.6 / 255, y: -0.6 / 255, z: -0.6 / 255, w: 0),
            ])
            .cropped(to: rect)
        let dithered = noise.map { $0.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: lit]) } ?? lit

        let context = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB, .workingFormat: CIFormat.RGBAh])
        return context.createCGImage(dithered, from: rect, format: .RGBA8, colorSpace: sRGB)
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

    /// The field for `image` in the current skin's dark display, or nil when the display has no
    /// room above its own colour.
    @MainActor static func field(for image: NSImage) -> Field? {
        let skin = SkinStore.active.withLock { $0 }
        if let last, last.image === image, last.skin == skin.id { return last.field }
        guard let dark = NSAppearance(named: .darkAqua) else { return nil }
        let display = skin.color(.display, for: dark)
        let ceiling = Self.ceiling(for: skin.color(.displayMuted, for: dark))
        let field = ceiling > luminance(display) + 0.002
            ? Self.field(of: image, ceiling: ceiling, display: display).map { Field(image: $0, id: ObjectIdentifier(image)) }
            : nil
        last = (image, skin.id, field)
        return field
    }

    /// The last cover rendered: the ambient view asks every second.
    @MainActor private static var last: (image: NSImage, skin: String, field: Field?)?
}

/// The glow's breath with the music: it follows the bass's loudness, quick to swell (50 ms) and
/// slow to settle (450 ms), like a lamp on a dimmer that someone is playing with.
final class GlowPulse {
    private(set) var level = 0.0
    private var last: Date?

    /// `bass`: the equalizer's bands in dBFS (the lowest three are used), or nil when nothing plays.
    func update(at date: Date, bands: [Float]?) -> Double {
        let dt = min(max(date.timeIntervalSince(last ?? date), 0), 0.1)
        last = date
        let loudest = bands.map { Double($0.prefix(3).max() ?? -120) } ?? -120
        let target = min(max((loudest + 42) / 30, 0), 1)
        let time = target > level ? 0.05 : 0.45
        level += (target - level) * (1 - exp(-dt / time))
        return level
    }
}

/// The cover's field behind the ambient faces. On the Display face it breathes with the bass,
/// between 70% and full, so it never passes the contrast the field was made for.
struct AmbientGlow: View {
    let field: ArtworkGlow.Field
    let pulses: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var pulse = GlowPulse()

    var body: some View {
        let image = Image(decorative: field.image, scale: 1).resizable().interpolation(.high)
        if pulses, !isSnapshot {
            let player = model.player
            let spectrum = player.equalizer.spectrum
            TimelineView(.animation(minimumInterval: nil, paused: !player.isPlaying)) { context in
                let bands = player.isPlaying ? spectrum.levels(at: player.avPlayer.currentTime().seconds) : nil
                image.opacity(0.7 + 0.3 * pulse.update(at: context.date, bands: bands))
            }
            .onAppear { spectrum.watch(true) }
            .onDisappear { spectrum.watch(false) }
            .allowsHitTesting(false)
        } else {
            image.allowsHitTesting(false)
        }
    }
}
