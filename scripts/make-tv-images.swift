// README and site images for NuVa on Android TV, from 1920×1080 screenshots of the app
// (`adb exec-out screencap -p > <name>.png` on a TV or the Android TV emulator).
// Usage, from the repository root:
//   swift scripts/make-tv-images.swift <screenshots-folder> docs/screenshots
// The folder holds queue, folders, equalizer, display, spectrum, needles, valves, orange and phosphor (.png).
// The top-right readout of the needles, valves and display faces (the server's address) is painted over:
// it would show a test server's.
import AppKit

let args = CommandLine.arguments
let snaps = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "docs/screenshots")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func load(_ name: String) -> NSImage {
    NSImage(contentsOf: snaps.appendingPathComponent("\(name).png"))!
}

/// Draws on a transparent canvas with a top-left origin and writes the PNG.
func canvas(_ size: CGSize, _ name: String, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print(name)
}

/// A TV screen: the screenshot with rounded corners and a soft shadow, as the Mac images' windows.
/// `hideReadout` covers an ambient face's top-right readout with the face's own background.
func screen(_ image: NSImage, in rect: CGRect, radius: Double, hideReadout: Bool = false) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    if hideReadout {
        // A patch of empty background from just above the readout (NSImage rects start at the bottom).
        let k = rect.width / 1920
        image.draw(in: CGRect(x: rect.minX + 1300 * k, y: rect.minY + 240 * k, width: 460 * k, height: 76 * k),
                   from: CGRect(x: 1300, y: 1080 - 236, width: 460, height: 76),
                   operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    NSGraphicsContext.restoreGraphicsState()
}

let margin = 48.0

/// One screen, 1600 wide.
func single(_ name: String, _ file: String) {
    let w = 1600.0 - 2 * margin, h = w * 9 / 16
    canvas(CGSize(width: 1600, height: h + 2 * margin), file) {
        screen(load(name), in: CGRect(x: margin, y: margin, width: w, height: h), radius: 20)
    }
}

/// Screens in a grid, 1600 wide.
func grid(_ names: [String], columns: Int, _ file: String, hideReadout: Set<String> = []) {
    let images = names.map(load)
    let gap = 40.0
    let w = (1600 - 2 * margin - gap * Double(columns - 1)) / Double(columns), h = w * 9 / 16
    let rows = (images.count + columns - 1) / columns
    canvas(CGSize(width: 1600, height: 2 * margin + Double(rows) * h + Double(rows - 1) * gap), file) {
        for (i, (name, img)) in zip(names, images).enumerated() {
            let x = margin + Double(i % columns) * (w + gap), y = margin + Double(i / columns) * (h + gap)
            screen(img, in: CGRect(x: x, y: y, width: w, height: h), radius: 14, hideReadout: hideReadout.contains(name))
        }
    }
}

single("queue", "tv.png")
single("folders", "tv-folders.png")
single("equalizer", "tv-equalizer.png")
grid(["needles", "valves", "display", "spectrum"], columns: 2, "tv-ambient.png",
     hideReadout: ["needles", "valves", "display"])
grid(["orange", "phosphor"], columns: 1, "tv-skins.png")
