import SwiftUI

/// Transporte à esquerda; repetir, aleatório e AirPlay à direita.
struct ControlBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var player = model.player
        HStack(spacing: Space.s1) {
            key("backward.end", .md, "Anterior ⌘←") { player.previous() }
            key(player.isPlaying ? "pause.fill" : "play.fill", .lg,
                player.isPlaying ? "Pausa Espaço" : "Tocar Espaço") { model.playOrBrowse() }
            key("forward.end", .md, "Seguinte ⌘→") { player.next() }
            key("stop", .md, "Parar") { player.stop() }

            Spacer(minLength: Space.s4)

            key(player.repeatMode == .one ? "repeat.1" : "repeat", .sm, repeatHelp(player.repeatMode),
                isOn: player.repeatMode != .off) { player.repeatMode = player.repeatMode.next }
            key("shuffle", .sm, player.shuffle ? "Aleatório ligado" : "Aleatório", isOn: player.shuffle) {
                player.shuffle.toggle()
            }
            AirPlayKey()
        }
    }

    private func repeatHelp(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Repetir"
        case .all: "Repetir tudo"
        case .one: "Repetir uma"
        }
    }

    private func key(
        _ symbol: String, _ size: KeyButtonStyle.KeySize, _ help: String,
        isOn: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.key(size, isOn: isOn))
            .keyFocus()
            .help(help)
    }
}

/// Tecla AirPlay. O seletor de destino nativo entra no passo de sistema.
struct AirPlayKey: View {
    var body: some View {
        Button {} label: { Image(systemName: "airplayaudio") }
            .buttonStyle(.key(.sm))
            .keyFocus()
            .help("AirPlay")
    }
}
