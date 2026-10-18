#if DEBUG
import AppKit
import SwiftUI

/// Debug only: `NuVa --snapshot` writes PNGs of the window in both themes
/// to NSTemporaryDirectory() and exits. Used to review the UI without opening the window.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--snapshot") else { return }
        let model = sampleModel()
        let browserModel = sampleBrowserModel()
        let compactModel = sampleModel()
        compactModel.windowMode = .compact
        let firstRunModel = sampleFirstRunModel()
        let artworkModel = sampleModel()
        artworkModel.showsArtwork = true
        if let entry = artworkModel.player.current?.entry {
            artworkModel.artwork.debugSet(sampleArtwork(), for: entry)
        }
        // With the browser's source (already saved in settings), but no queue.
        let emptyQueueModel = AppModel(defaults: UserDefaults(suiteName: "snapshot-browser")!)
        emptyQueueModel.windowMode = .player
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let views: [(String, AnyView, AppModel)] = [
            ("player", AnyView(ContentView()), model),
            ("navegador", AnyView(ContentView()), browserModel),
            ("compacto", AnyView(ContentView()), compactModel),
            ("primeiro", AnyView(ContentView()), firstRunModel),
            ("fila-vazia", AnyView(ContentView()), emptyQueueModel),
            ("teclas", AnyView(KeyPreview().frame(width: 360, height: 480)), model),
            ("barra", AnyView(MenuBarPlayer()), model),
            ("equalizador", AnyView(EqualizerPanel(eq: model.player.equalizer)), model),
            ("player-capa", AnyView(ContentView()), artworkModel),
            ("barra-capa", AnyView(MenuBarPlayer()), artworkModel),
        ]
        // Every view in Nuno; the main ones again with SF Pro + SF Mono ("-sf") and in each
        // Graphite skin (always dark, so one file per view).
        let main: Set<String> = ["player", "navegador", "compacto", "barra", "equalizador"]
        let bothThemes = [(ColorScheme.dark, "chumbo"), (.light, "aluminio")]
        let runs: [(Skin, FontSet, String, Set<String>?, [(ColorScheme, String)])] = [
            (.nuno, .inter, "", nil, bothThemes),
            (.nuno, .system, "-sf", main, bothThemes),
            (.graphiteOrange, .system, "", main, [(.dark, Skin.graphiteOrange.id)]),
            (.graphiteGreen, .system, "", main, [(.dark, Skin.graphiteGreen.id)]),
        ]
        for (skin, fontSet, suffix, only, themes) in runs {
            SkinStore.active.withLock { $0 = skin }
            SkinStore.activeFonts.withLock { $0 = fontSet }
            for (viewName, view, model) in views where only?.contains(viewName) ?? true {
                for (scheme, name) in themes {
                    let content = view
                        .environment(model)
                        .environment(\.isSnapshot, true)
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    if let image = renderer.nsImage,
                       let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("snapshot-\(viewName)\(suffix)-\(name).png"))
                    }
                }
            }
        }
        print(dir.path)
        exit(0)
    }

    @MainActor
    static func sampleModel() -> AppModel {
        let model = AppModel(defaults: UserDefaults(suiteName: "snapshot")!)
        let id = UUID()
        let names = [
            "01 - Second Hand News.flac", "02 - Dreams.flac", "03 - Never Going Back Again.flac",
            "04 - Don’t Stop.flac", "05 - Go Your Own Way.flac", "06 - Songbird.flac",
            "07 - The Chain.flac", "08 - You Make Loving Fun.flac", "09 - I Don’t Want to Know.flac",
            "10 - Oh Daddy.flac", "11 - Gold Dust Woman.flac",
        ]
        let entries = names.map {
            Entry(sourceID: id, path: "Fleetwood Mac/Rumours (1977)/\($0)", name: $0, kind: .track)
        }
        let lengths: [Double] = [163, 257, 122, 191, 218, 200, 270, 211, 196, 234, 296]
        for (e, d) in zip(entries, lengths) { model.durations.debugSet(e, d) }
        model.player.debugSet(queue: entries, current: 1, time: 67, duration: 257, format: "FLAC 24/48 · 1669 kbps")
        model.windowMode = .player
        model.output.debugSet("→ AirPlay WiiM")
        // Equalizer on with a preset, so the snapshot shows the bands.
        model.player.equalizer.apply(Equalizer.presets.first { $0.name == "Rock" } ?? Equalizer.presets[0])
        model.player.equalizer.enabled = true
        return model
    }

    /// A made-up cover (no real album art in the repository): bands of colour, like a 70s sleeve.
    static func sampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            let colors = ["#E8D9B5", "#D9A441", "#C2562B", "#7A2E2A", "#2F3B45"].map { hex -> NSColor in
                let v = UInt64(hex.dropFirst(), radix: 16)!
                return NSColor(srgbRed: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
                               blue: Double(v & 0xff) / 255, alpha: 1)
            }
            let band = rect.height / CGFloat(colors.count)
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSRect(x: 0, y: CGFloat(i) * band, width: rect.width, height: band).fill()
            }
            NSColor(white: 1, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 380, y: 380, width: 140, height: 140)).fill()
            return true
        }
    }

    /// First launch: no sources and no queue.
    @MainActor
    static func sampleFirstRunModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "snapshot-first")!
        defaults.removePersistentDomain(forName: "snapshot-first")
        let model = AppModel(defaults: defaults)
        model.windowMode = .player
        return model
    }

    /// Fake Local source (empty files) in the container, open in the browser.
    @MainActor
    static func sampleBrowserModel() -> AppModel {
        let defaults = UserDefaults(suiteName: "snapshot-browser")!
        defaults.removePersistentDomain(forName: "snapshot-browser")
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Música")
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        let artist = root.appendingPathComponent("Fleetwood Mac")
        let albums = ["Rumours (1977)": 11, "Tango in the Night (1987)": 12, "Fleetwood Mac (1975)": 0]
        for (album, count) in albums {
            let dir = artist.appendingPathComponent(album)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<count {
                fm.createFile(atPath: dir.appendingPathComponent(String(format: "%02d - Faixa.flac", i + 1)).path, contents: nil)
            }
        }
        for cd in ["CD 01", "CD 02"] {
            try? fm.createDirectory(at: artist.appendingPathComponent("Tusk (1979)/\(cd)"), withIntermediateDirectories: true)
        }
        let model = AppModel(defaults: defaults)
        model.windowMode = .browser
        guard let source = model.sources.addLocal(root) else { return model }
        model.browser.open(BrowserLocation(sourceID: source.id, path: "Fleetwood Mac"))
        // Lets the listing and summaries finish before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        for e in model.browser.entries {
            Task { await model.browser.loadSummary(e) }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let player = sampleModel().player
        model.player.debugSet(
            queue: player.queue.map(\.entry), current: 1, time: 67, duration: 257, format: "FLAC 24/48 · 1669 kbps")
        return model
    }
}
#endif
