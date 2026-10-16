import AVKit
import SwiftUI

/// Transporte à esquerda; gaveta das pastas, repetir, aleatório e AirPlay à direita.
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

            Spacer(minLength: Space.s2)

            key("sidebar.left", .sm, model.windowMode == .browser ? "Esconder pastas ⌘B" : "Mostrar pastas ⌘B",
                isOn: model.windowMode == .browser) { model.toggleBrowser() }
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
        .buttonStyle(.key(.sm))
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
        let ink = NSColor(named: "ink") ?? .labelColor
        for state in [AVRoutePickerView.ButtonState.normal, .normalHighlighted, .active, .activeHighlighted] {
            view.setRoutePickerButtonColor(ink, for: state)
        }
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}
