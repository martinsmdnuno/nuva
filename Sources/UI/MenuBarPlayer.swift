import SwiftUI

/// Mini player in the menu bar. Stays when the window closes: the music keeps playing.
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
                Menu {
                    Button(Ambient.shared.isOpen ? String(localized: "Sair do Ambiente") : String(localized: "Ambiente")) {
                        Ambient.shared.toggle(model)
                    }
                    Divider()
                    SkinMenuItems()
                } label: { Image(systemName: "circle.lefthalf.filled") }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.key(.mode))
                    .keyFocus()
                    .fixedSize()
                    .help("Ambiente e skin")
                Button("Abrir NuVa") { openMain() }
                    .buttonStyle(.keyText)
                    .keyFocus()
                Button("Sair") { NSApp.terminate(nil) }
                    .buttonStyle(.keyText)
                    .keyFocus()
            }
        }
        .padding(Space.s3)
        .frame(width: 360)
        .background(Color.surface0)
        .id(SkinStore.shared.renderID)
    }

    private func openMain() {
        DockPresence.show(true)
        openWindow(id: "main")
        NSApp.activate()
    }

    private func key(
        _ symbol: String, _ tone: KeyButtonStyle.Tone, _ help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { KeySymbol(name: symbol) }
            .buttonStyle(.key(tone))
            .keyFocus()
            .help(help)
    }
}
