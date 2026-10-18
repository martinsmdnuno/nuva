// README images from the app's screenshots: windows with a macOS frame and the hero image.
// Usage, from the repository root:
//   NuVa.app/Contents/MacOS/NuVa --snapshot -AppleLanguages '(en)'   (prints the screenshots folder)
//   swift scripts/make-readme-images.swift <screenshots-folder> docs/screenshots
import AppKit
import CoreText

let args = CommandLine.arguments
let snaps = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args.count > 2 ? args[2] : "docs/screenshots")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for name in ["Inter.ttf", "IBMPlexMono-Regular.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Resources/Fonts/\(name)") as CFURL, .process, nil)
}

func color(_ hex: String, _ alpha: Double = 1) -> NSColor {
    let v = UInt64(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                   blue: Double(v & 0xff) / 255, alpha: alpha)
}

func inter(_ size: Double, _ weight: NSFont.Weight) -> NSFont {
    let desc = NSFontDescriptor(fontAttributes: [.family: "Inter", .traits: [NSFontDescriptor.TraitKey.weight: weight]])
    return NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

func snapshot(_ name: String) -> NSImage {
    NSImage(contentsOf: snaps.appendingPathComponent("snapshot-\(name).png"))!
}

/// Size in pixels (screenshots are at 2x).
func px(_ image: NSImage) -> CGSize {
    let rep = image.representations.first!
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

/// Draws on a canvas with a top-left origin and writes the PNG.
func canvas(_ size: CGSize, _ name: String, background: NSColor? = nil, draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    if let background {
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
    }
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print(name)
}

enum Chrome { case window(dark: Bool), popover }

let titleBar = 56.0
let radius = 22.0

/// Size of the framed window for a screenshot, at scale `k`.
func framedSize(_ image: NSImage, _ chrome: Chrome, k: Double) -> CGSize {
    let s = px(image)
    if case .window = chrome { return CGSize(width: s.width * k, height: (s.height + titleBar) * k) }
    return CGSize(width: s.width * k, height: s.height * k)
}

/// A macOS window (title bar with traffic lights) or a popover, with a shadow.
func drawFramed(_ image: NSImage, _ chrome: Chrome, at origin: CGPoint, k: Double) {
    let size = framedSize(image, chrome, k: k)
    let rect = CGRect(origin: origin, size: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius * k, yRadius: radius * k)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
    shadow.shadowBlurRadius = 70 * k
    shadow.shadowOffset = NSSize(width: 0, height: -24 * k)
    shadow.set()
    color("#1E2023").setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    var contentY = origin.y
    if case .window(let dark) = chrome {
        let bar = CGRect(x: origin.x, y: origin.y, width: size.width, height: titleBar * k)
        (dark ? color("#2B2D30") : color("#ECEBE8")).setFill()
        bar.fill()
        for (i, c) in ["#FF5F57", "#FEBC2E", "#28C840"].enumerated() {
            color(c).setFill()
            NSBezierPath(ovalIn: CGRect(x: origin.x + (28 + Double(i) * 40) * k, y: origin.y + 16 * k,
                                        width: 24 * k, height: 24 * k)).fill()
        }
        let title = NSAttributedString(string: "NuVa", attributes: [
            .font: inter(26 * k, .semibold), .foregroundColor: dark ? color("#C9C6BF") : color("#4A4C50"),
        ])
        title.draw(at: CGPoint(x: origin.x + 156 * k, y: origin.y + 13 * k))
        (dark ? color("#000000", 0.4) : color("#000000", 0.12)).setFill()
        CGRect(x: origin.x, y: origin.y + titleBar * k - k, width: size.width, height: k).fill()
        contentY += titleBar * k
    }
    let s = px(image)
    image.draw(in: CGRect(x: origin.x, y: contentY, width: s.width * k, height: s.height * k),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    // Thin outline, like system windows.
    NSColor(white: 1, alpha: 0.08).setStroke()
    path.lineWidth = k
    path.stroke()
}

/// One or more windows side by side on a transparent background, with room for the shadow.
func framed(_ items: [(NSImage, Chrome)], name: String, k: Double = 1, gap: Double = 64) {
    let sizes = items.map { framedSize($0.0, $0.1, k: k) }
    let pad = 110.0
    let width = sizes.map(\.width).reduce(0, +) + gap * Double(items.count - 1) + pad * 2
    let height = (sizes.map(\.height).max() ?? 0) + pad * 2
    canvas(CGSize(width: width, height: height), name) {
        var x = pad
        for (item, size) in zip(items, sizes) {
            drawFramed(item.0, item.1, at: CGPoint(x: x, y: pad), k: k)
            x += size.width + gap
        }
    }
}

// Hero: icon, name and tagline on top; browser in Lead and player in Aluminium below.
let browser = snapshot("navegador-chumbo")
let playerLight = snapshot("player-aluminio")
let heroSize = CGSize(width: 2400, height: 1480)
canvas(heroSize, "hero.png", background: color("#1E2023")) {
    let icon = NSImage(contentsOfFile: "docs/brand/icon-1024.png")!
    icon.draw(in: CGRect(x: heroSize.width / 2 - 330, y: 78, width: 150, height: 150),
              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSAttributedString(string: "NuVa", attributes: [.font: inter(108, .semibold), .foregroundColor: color("#E8E6E1")])
        .draw(at: CGPoint(x: heroSize.width / 2 - 160, y: 86))
    let tagline = NSAttributedString(string: "Your music folders, played as they are.", attributes: [
        .font: inter(44, .regular), .foregroundColor: color("#A3A19C"),
    ])
    tagline.draw(at: CGPoint(x: (heroSize.width - tagline.size().width) / 2, y: 262))

    let k = 0.88
    let b = framedSize(browser, .window(dark: true), k: k)
    let p = framedSize(playerLight, .window(dark: false), k: k)
    let overlap = 200.0
    let left = (heroSize.width - (b.width + p.width - overlap)) / 2
    drawFramed(browser, .window(dark: true), at: CGPoint(x: left, y: 400), k: k)
    drawFramed(playerLight, .window(dark: false), at: CGPoint(x: left + b.width - overlap, y: 470), k: k)
}

framed([(snapshot("navegador-chumbo"), .window(dark: true))], name: "browser.png")
framed([(snapshot("player-chumbo"), .window(dark: true)), (snapshot("player-aluminio"), .window(dark: false))],
       name: "themes.png")
framed([(snapshot("compacto-chumbo"), .window(dark: true))], name: "compact.png")
framed([(snapshot("primeiro-chumbo"), .window(dark: true))], name: "first-run.png")
framed([(snapshot("equalizador-chumbo"), .popover)], name: "equalizer.png")
framed([(snapshot("barra-chumbo"), .popover)], name: "menubar.png")
