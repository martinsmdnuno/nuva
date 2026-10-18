import SwiftUI

/// Mini player na barra de menus. Fica quando a janela fecha: a música continua.
struct MenuBarPlayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let player = model.player
        VStack(spacing: Space.s3) {
            DisplayView()
            HStack(spacing: Space.s1) {
                key("backward.end", .transport, String(localized: "Anterior")) { player.previous() }
                key(player.isPlaying ? "pause.fill" : "play.fill", .play, player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar")) {
                    if player.queue.isEmpty { openMain() } else { player.togglePlayPause() }
                }
                key("forward.end", .transport, String(localized: "Seguinte")) { player.next() }
                Spacer(minLength: Space.s2)
                Button("Abrir NuVa") { openMain() }
                    .buttonStyle(.keyText)
                Button("Sair") { NSApp.terminate(nil) }
                    .buttonStyle(.keyText)
            }
        }
        .padding(Space.s3)
        .frame(width: 320)
        .background(Color.surface0)
    }

    private func openMain() {
        DockPresence.show(true)
        openWindow(id: "main")
        NSApp.activate()
    }

    private func key(
        _ symbol: String, _ tone: KeyButtonStyle.Tone, _ help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.key(tone))
            .help(help)
    }
}
