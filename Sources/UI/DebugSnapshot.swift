#if DEBUG
import AppKit
import SwiftUI

/// Só em Debug: `NuVa --snapshot` grava PNG das vistas nos dois temas
/// em NSTemporaryDirectory() e sai. Serve para rever a UI sem abrir a janela.
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--snapshot") else { return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        for (scheme, name) in [(ColorScheme.dark, "chumbo"), (.light, "aluminio")] {
            let view = ContentView().environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("snapshot-\(name).png"))
            }
        }
        print(dir.path)
        exit(0)
    }
}
#endif
