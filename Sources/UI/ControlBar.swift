import AVKit
import SwiftUI

/// Teclas em três grupos com legenda, como no Braun TG 60:
/// leitura (anterior, play/pausa, seguinte) · modo (repetir, aleatório) · saída (AirPlay, equalizador).
/// Parar e mostrar pastas ficam só no menu e nos atalhos (⌘. e ⌘B).
struct ControlBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var player = model.player
        HStack(alignment: .top, spacing: 0) {
            group("leitura") {
                key("backward.end", .transport, String(localized: "Anterior ⌘←")) { player.previous() }
                key(player.isPlaying ? "pause.fill" : "play.fill", .play,
                    player.isPlaying ? String(localized: "Pausa Espaço") : String(localized: "Tocar Espaço")) { model.playOrBrowse() }
                key("forward.end", .transport, String(localized: "Seguinte ⌘→")) { player.next() }
            }
            Spacer(minLength: Space.s4)
            group("modo") {
                key(player.repeatMode == .one ? "repeat.1" : "repeat", .mode, repeatHelp(player.repeatMode) + " ⌘R",
                    led: player.repeatMode != .off) { player.repeatMode = player.repeatMode.next }
                key("shuffle", .mode, player.shuffle ? String(localized: "Aleatório ligado ⌥⌘S") : String(localized: "Aleatório ⌥⌘S"),
                    led: player.shuffle) { player.shuffle.toggle() }
            }
            Spacer(minLength: Space.s4)
            group("saída") {
                AirPlayKey().keyLED(nil)
                EqualizerKey()
            }
        }
    }

    private func repeatHelp(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: String(localized: "Repetir")
        case .all: String(localized: "Repetir tudo")
        case .one: String(localized: "Repetir uma")
        }
    }

    private func group(_ name: LocalizedStringKey, @ViewBuilder keys: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s1 + 2) {
            HStack(alignment: .bottom, spacing: Space.s1) { keys() }
            Text(name).legend()
        }
    }

    private func key(
        _ symbol: String, _ tone: KeyButtonStyle.Tone, _ help: String,
        led: Bool? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.key(tone))
            .keyFocus()
            .help(help)
            .keyLED(led)
    }
}

/// Tecla AirPlay: o seletor de destino nativo (AVRoutePickerView) dentro da tecla.
struct AirPlayKey: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        Button {} label: {
            if isSnapshot {
                Image(systemName: "airplayaudio")
            } else {
                RoutePicker(player: model.player.avPlayer).frame(width: 20, height: 20)
            }
        }
        .buttonStyle(.key(.mode))
        .keyFocus()
        .help("AirPlay")
    }
}

private struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        let ink = NSColor(named: "key-mode-ink") ?? .labelColor
        for state in [AVRoutePickerView.ButtonState.normal, .normalHighlighted, .active, .activeHighlighted] {
            view.setRoutePickerButtonColor(ink, for: state)
        }
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}
