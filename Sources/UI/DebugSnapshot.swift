#if DEBUG
import AppKit
import SwiftUI

/// Só em Debug: `NuVa --snapshot` grava PNG da janela nos dois temas
/// em NSTemporaryDirectory() e sai. Serve para rever a UI sem abrir a janela.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--snapshot") else { return }
        let model = sampleModel()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let views: [(String, AnyView)] = [
            ("player", AnyView(ContentView())),
            ("teclas", AnyView(KeyPreview().frame(width: 360, height: 480))),
        ]
        for (viewName, view) in views {
            for (scheme, name) in [(ColorScheme.dark, "chumbo"), (.light, "aluminio")] {
                let content = view
                    .environment(model)
                    .environment(\.isSnapshot, true)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("snapshot-\(viewName)-\(name).png"))
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
        model.player.debugSet(queue: entries, current: 1, time: 67, duration: 257, format: "FLAC 24/48")
        return model
    }
}
#endif
