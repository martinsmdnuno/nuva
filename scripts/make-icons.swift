// Gera o ícone da NuVa a partir das mesmas medidas: PNG (CoreGraphics) e SVG.
// Uso: swift scripts/make-icons.swift <pasta-de-saída> [variante: folder|device|display|key] [--all]
// Corre na raiz do repositório: o logótipo usa Resources/Fonts/IBMPlexMono-Medium.ttf.
// Cores de docs/design-system/tokens.json (tema Chumbo).
import AppKit
import Foundation

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon-out")
let variant = args.count > 2 && !args[2].hasPrefix("--") ? args[2] : "folder"
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

struct C { static let surface0 = "#1E2023", surface1 = "#2B2D30", display = "#141517", displayInk = "#E8E6E1",
           displayMuted = "#8E8C87", line = "#44474B", keyFace = "#3A3D41", keyEdge = "#74787D",
           track = "#44474B", fill = "#C9C6BF", signal = "#E0A93E", ink = "#E8E6E1" }

/// Uma forma do ícone, em coordenadas de 1024 com origem no canto superior esquerdo.
enum Shape {
    case rect(x: Double, y: Double, w: Double, h: Double, r: Double, fill: String, stroke: String? = nil, sw: Double = 0)
    case circle(cx: Double, cy: Double, r: Double, fill: String)
    case triangle([(Double, Double)], fill: String)
}

/// Grelha dos ícones do macOS: corpo de 824 com raio 185, centrado em 1024.
let body = (x: 100.0, y: 100.0, w: 824.0, h: 824.0, r: 185.0)

/// Pasta com medidor de VU, em coordenadas de 0 a 100. A versão pequena tem menos barras e um LED maior.
func folderGlyph(small: Bool) -> [Shape] {
    if small {
        return [
            .rect(x: 8, y: 12, w: 30, h: 24, r: 7, fill: C.display),
            .triangle([(20, 12), (38, 12), (50, 24), (20, 24)], fill: C.display),
            .rect(x: 8, y: 22, w: 84, h: 66, r: 8, fill: C.display),
            .circle(cx: 21, cy: 20, r: 5.5, fill: C.signal),
            .rect(x: 20, y: 52, w: 14, h: 26, r: 3, fill: C.displayInk),
            .rect(x: 43, y: 38, w: 14, h: 40, r: 3, fill: C.displayInk),
            .rect(x: 66, y: 56, w: 14, h: 22, r: 3, fill: C.displayInk),
        ]
    }
    let bars: [(x: Double, h: Double)] = [(22.5, 18), (34.5, 30), (46.5, 40), (58.5, 26), (70.5, 14)]
    return [
        .rect(x: 8, y: 14, w: 30, h: 22, r: 6, fill: C.display),
        .triangle([(20, 14), (36, 14), (46, 24), (20, 24)], fill: C.display),
        .rect(x: 8, y: 24, w: 84, h: 64, r: 7, fill: C.display),
        .circle(cx: 19, cy: 20.5, r: 3.6, fill: C.signal),
    ] + bars.map { .rect(x: $0.x, y: 78 - $0.h, w: 7, h: $0.h, r: 2, fill: C.displayInk) }
}

/// Escala e desloca formas de 0–100 para o ícone.
func place(_ shapes: [Shape], x: Double, y: Double, k: Double) -> [Shape] {
    func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    return shapes.map {
        switch $0 {
        case let .rect(rx, ry, w, h, r, fill, stroke, sw):
            return .rect(x: r2(x + rx * k), y: r2(y + ry * k), w: r2(w * k), h: r2(h * k), r: r2(r * k), fill: fill, stroke: stroke, sw: r2(sw * k))
        case let .circle(cx, cy, r, fill):
            return .circle(cx: r2(x + cx * k), cy: r2(y + cy * k), r: r2(r * k), fill: fill)
        case let .triangle(points, fill):
            return .triangle(points.map { (r2(x + $0.0 * k), r2(y + $0.1 * k)) }, fill: fill)
        }
    }
}

func shapes(small: Bool) -> [Shape] {
    var s: [Shape] = [.rect(x: body.x, y: body.y, w: body.w, h: body.h, r: body.r, fill: C.surface1, stroke: C.line, sw: 8)]
    switch variant {
    case "folder":
        // Pasta com VU, centrada no corpo. Em 16 e 32 px, a versão simplificada e maior.
        s += small ? place(folderGlyph(small: true), x: 192, y: 192, k: 6.4)
                   : place(folderGlyph(small: false), x: 232, y: 226.4, k: 5.6)
    case "display":
        // Só o display, grande, com LED e barra.
        s += [
            .rect(x: 180, y: 300, w: 664, h: 424, r: 56, fill: C.display),
            .circle(cx: 276, cy: 396, r: 30, fill: C.signal),
            .rect(x: 256, y: 600, w: 512, h: 24, r: 12, fill: C.track),
            .rect(x: 256, y: 600, w: 220, h: 24, r: 12, fill: C.fill),
        ]
        if !small { s.append(.rect(x: 256, y: 480, w: 360, h: 40, r: 20, fill: C.displayInk)) }
    case "key":
        // Uma tecla de play grande, com o LED por cima.
        s += [
            .circle(cx: 512, cy: 250, r: 28, fill: C.signal),
            .rect(x: 262, y: 352, w: 500, h: 420, r: 64, fill: C.keyFace, stroke: C.keyEdge, sw: 10),
            .rect(x: 272, y: 744, w: 480, h: 12, r: 6, fill: "#00000059"),
            .triangle([(450, 452), (450, 672), (632, 562)], fill: C.ink),
        ]
    default:  // "device"
        // Frente do aparelho: display com LED, título e progresso; três teclas por baixo.
        if small {
            s += [
                .rect(x: 180, y: 260, w: 664, h: 504, r: 64, fill: C.display),
                .circle(cx: 300, cy: 380, r: 44, fill: C.signal),
                .rect(x: 270, y: 600, w: 484, h: 40, r: 20, fill: C.fill),
            ]
        } else {
            s += [
                .rect(x: 196, y: 220, w: 632, h: 340, r: 48, fill: C.display),
                .circle(cx: 280, cy: 300, r: 22, fill: C.signal),
                .rect(x: 256, y: 372, w: 340, h: 30, r: 15, fill: C.displayInk),
                .rect(x: 256, y: 420, w: 210, h: 22, r: 11, fill: C.displayMuted),
                .rect(x: 256, y: 490, w: 512, h: 16, r: 8, fill: C.track),
                .rect(x: 256, y: 490, w: 210, h: 16, r: 8, fill: C.fill),
            ]
            let keys: [(x: Double, y: Double, w: Double, h: Double)] = [
                (196, 640, 170, 120), (397, 624, 230, 152), (658, 640, 170, 120),
            ]
            for k in keys {
                s.append(.rect(x: k.x, y: k.y, w: k.w, h: k.h, r: 24, fill: C.keyFace, stroke: C.keyEdge, sw: 6))
                s.append(.rect(x: k.x + 6, y: k.y + k.h - 14, w: k.w - 12, h: 8, r: 4, fill: "#00000059"))
            }
            // Anterior | play | seguinte, em `ink`.
            s += [
                .triangle([(300, 676), (300, 724), (262, 700)], fill: C.ink),
                .rect(x: 250, y: 676, w: 9, h: 48, r: 2, fill: C.ink),
                .triangle([(486, 660), (486, 740), (552, 700)], fill: C.ink),
                .triangle([(724, 676), (724, 724), (762, 700)], fill: C.ink),
                .rect(x: 765, y: 676, w: 9, h: 48, r: 2, fill: C.ink),
            ]
        }
    }
    return s
}

func color(_ hex: String) -> CGColor {
    let h = hex.dropFirst()
    let v = UInt64(h, radix: 16)!
    if h.count == 8 {
        return CGColor(srgbRed: Double((v >> 24) & 0xff) / 255, green: Double((v >> 16) & 0xff) / 255,
                       blue: Double((v >> 8) & 0xff) / 255, alpha: Double(v & 0xff) / 255)
    }
    return CGColor(srgbRed: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                   blue: Double(v & 0xff) / 255, alpha: 1)
}

func png(_ px: Int, name: String, shadow: Bool = true, art: [Shape]? = nil) {
    let small = px <= 32
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = Double(px) / 1024
    ctx.translateBy(x: 0, y: Double(px))
    ctx.scaleBy(x: k, y: -k)
    for (i, shape) in (art ?? shapes(small: small)).enumerated() {
        ctx.saveGState()
        if i == 0, shadow, !small {
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
        }
        switch shape {
        case let .rect(x, y, w, h, r, fill, stroke, sw):
            let path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
            ctx.addPath(path); ctx.setFillColor(color(fill)); ctx.fillPath()
            if let stroke, sw > 0, !(small && i == 0) {
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
                let inset = CGRect(x: x + sw / 2, y: y + sw / 2, width: w - sw, height: h - sw)
                ctx.addPath(CGPath(roundedRect: inset, cornerWidth: r - sw / 2, cornerHeight: r - sw / 2, transform: nil))
                ctx.setStrokeColor(color(stroke)); ctx.setLineWidth(sw); ctx.strokePath()
            }
        case let .circle(cx, cy, r, fill):
            ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            ctx.setFillColor(color(fill)); ctx.fillPath()
        case let .triangle(points, fill):
            ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
            ctx.closePath(); ctx.setFillColor(color(fill)); ctx.fillPath()
        }
        ctx.restoreGState()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func fillAttr(_ hex: String) -> String {
    hex.count == 9 ? "fill=\"\(hex.prefix(7))\" fill-opacity=\"\(String(format: "%.2f", Double(UInt8(hex.suffix(2), radix: 16)!) / 255))\"" : "fill=\"\(hex)\""
}

func svgElements(_ shapes: [Shape], small: Bool) -> String {
    var body = ""
    for (i, shape) in shapes.enumerated() {
        switch shape {
        case let .rect(x, y, w, h, r, fill, stroke, sw):
            if let stroke, sw > 0, !(small && i == 0) {
                body += "  <rect x=\"\(x + sw / 2)\" y=\"\(y + sw / 2)\" width=\"\(w - sw)\" height=\"\(h - sw)\" rx=\"\(r - sw / 2)\" \(fillAttr(fill)) stroke=\"\(stroke)\" stroke-width=\"\(sw)\"/>\n"
            } else {
                body += "  <rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" rx=\"\(r)\" \(fillAttr(fill))/>\n"
            }
        case let .circle(cx, cy, r, fill):
            body += "  <circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(r)\" \(fillAttr(fill))/>\n"
        case let .triangle(points, fill):
            body += "  <polygon points=\"\(points.map { "\($0.0),\($0.1)" }.joined(separator: " "))\" \(fillAttr(fill))/>\n"
        }
    }
    return body
}

func svg(small: Bool) -> String {
    // Sem margem da grelha no favicon: recorta ao corpo.
    let viewBox = small ? "100 100 824 824" : "0 0 1024 1024"
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\">\n\(svgElements(shapes(small: small), small: small))</svg>\n"
}

/// Logótipo: pasta + "NuVa" em IBM Plex Mono Medium, com o texto em contornos.
func logoSVG(ink: String) -> String {
    let fontURL = URL(fileURLWithPath: "Resources/Fonts/IBMPlexMono-Medium.ttf") as CFURL
    let desc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL) as! [CTFontDescriptor])[0]
    let font = CTFontCreateWithFontDescriptor(desc, 66, nil)
    let text = Array("NuVa".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: text.count)
    CTFontGetGlyphsForCharacters(font, text, &glyphs, text.count)
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
    // Texto centrado na altura da pasta (14 a 88), afastado 32 da borda direita.
    let baseline = 51 + CTFontGetCapHeight(font) / 2
    var x = 124.0
    var d = ""
    for (g, adv) in zip(glyphs, advances) {
        var t = CGAffineTransform(translationX: x, y: baseline).scaledBy(x: 1, y: -1)
        if let path = CTFontCreatePathForGlyph(font, g, &t) {
            path.applyWithBlock { el in
                let p = el.pointee.points
                func f(_ q: CGPoint) -> String { String(format: "%.2f %.2f", q.x, q.y) }
                switch el.pointee.type {
                case .moveToPoint: d += "M\(f(p[0]))"
                case .addLineToPoint: d += "L\(f(p[0]))"
                case .addQuadCurveToPoint: d += "Q\(f(p[0])) \(f(p[1]))"
                case .addCurveToPoint: d += "C\(f(p[0])) \(f(p[1])) \(f(p[2]))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
        }
        x += adv.width
    }
    let w = Int(ceil(x)) - 8 + 4
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"8 12 \(w) 78\">\n"
        + svgElements(folderGlyph(small: false), small: false)
        + "  <path d=\"\(d)\" fill=\"\(ink)\"/>\n</svg>\n"
}

/// ICO com PNGs embebidos (aceite por todos os browsers atuais).
func ico(_ sizes: [Int], name: String) {
    let pngs = sizes.map { px -> Data in
        png(px, name: "_ico\(px).png", shadow: false)
        let url = out.appendingPathComponent("_ico\(px).png")
        defer { try? FileManager.default.removeItem(at: url) }
        return try! Data(contentsOf: url)
    }
    var data = Data([0, 0, 1, 0, UInt8(sizes.count), 0])
    var offset = 6 + 16 * sizes.count
    for (px, p) in zip(sizes, pngs) {
        data += [UInt8(px % 256), UInt8(px % 256), 0, 0, 1, 0, 32, 0]
        withUnsafeBytes(of: UInt32(p.count).littleEndian) { data += $0 }
        withUnsafeBytes(of: UInt32(offset).littleEndian) { data += $0 }
        offset += p.count
    }
    pngs.forEach { data += $0 }
    try! data.write(to: out.appendingPathComponent(name))
}

png(1024, name: "icon-1024.png")
try! svg(small: false).write(to: out.appendingPathComponent("icon.svg"), atomically: true, encoding: .utf8)
try! svg(small: true).write(to: out.appendingPathComponent("favicon.svg"), atomically: true, encoding: .utf8)
// Logótipo para fundos escuros (Chumbo) e claros (Alumínio).
try! logoSVG(ink: C.displayInk).write(to: out.appendingPathComponent("logo-chumbo.svg"), atomically: true, encoding: .utf8)
try! logoSVG(ink: "#1E2023").write(to: out.appendingPathComponent("logo-aluminio.svg"), atomically: true, encoding: .utf8)
if args.contains("--all") {
    // AppIcon.appiconset do macOS
    let set = out.appendingPathComponent("AppIcon.appiconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
            png(pt * scale, name: "AppIcon.appiconset/\(name)")
            images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: set.appendingPathComponent("Contents.json"))
    // Capa do Now Playing: quadrada e sem margem, o macOS arredonda os cantos.
    let artSet = out.appendingPathComponent("NowPlayingArtwork.imageset")
    try? FileManager.default.createDirectory(at: artSet, withIntermediateDirectories: true)
    let art = [Shape.rect(x: 0, y: 0, w: 1024, h: 1024, r: 0, fill: C.surface1)]
        + place(folderGlyph(small: false), x: 192, y: 185.6, k: 6.4)
    png(1024, name: "NowPlayingArtwork.imageset/artwork.png", shadow: false, art: art)
    let artContents: [String: Any] = ["images": [["idiom": "universal", "filename": "artwork.png"]],
                                      "info": ["author": "xcode", "version": 1]]
    try! JSONSerialization.data(withJSONObject: artContents, options: [.prettyPrinted, .sortedKeys])
        .write(to: artSet.appendingPathComponent("Contents.json"))
    // Favicons
    png(32, name: "favicon-32.png", shadow: false)
    png(180, name: "apple-touch-icon.png", shadow: false)
    png(512, name: "icon-512.png", shadow: false)
    ico([16, 32, 48], name: "favicon.ico")
}
print(out.path)
