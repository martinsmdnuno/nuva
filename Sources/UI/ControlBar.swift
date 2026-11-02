import SwiftUI

/// Keys in three groups with a legend, as on the Braun TG 60, play in the middle:
/// mode (shuffle, repeat) · playback (previous, play/pause, next) · volume (the knob).
/// The output and the equalizer live on the display; stop and show folders only in the
/// menu and shortcuts (⌘. and ⌘B).
struct ControlBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var player = model.player
        HStack(alignment: .top, spacing: Space.s4) {
            group("modo") {
                key("shuffle", .mode, player.shuffle ? String(localized: "Aleatório ligado ⌥⌘S") : String(localized: "Aleatório ⌥⌘S"),
                    led: player.shuffle) { player.shuffle.toggle() }
                key(player.repeatMode == .one ? "repeat.1" : "repeat", .mode, repeatHelp(player.repeatMode) + " ⌘R",
                    led: player.repeatMode != .off) { player.repeatMode = player.repeatMode.next }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            group("leitura") {
                key("backward.end", .transport, String(localized: "Anterior ⌘←")) { player.previous() }
                key(player.isPlaying ? "pause.fill" : "play.fill", .play,
                    player.isPlaying ? String(localized: "Pausa Espaço") : String(localized: "Tocar Espaço")) { model.playOrBrowse() }
                key("forward.end", .transport, String(localized: "Seguinte ⌘→")) { player.next() }
            }
            // Equal flexible sides keep the play key on the window's centre line.
            VStack(alignment: .trailing, spacing: Space.s1 + 2) {
                VolumeKnob().keyLED(nil)
                HStack(spacing: Space.s1 + 2) {
                    Text("volume").legend()
                    Text(VolumeKnob.reading(player.volume))
                        .font(.dsHint)
                        .foregroundStyle(Color.inkMuted)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
        Button(action: action) { KeySymbol(name: symbol) }
            .buttonStyle(.key(tone))
            .keyFocus()
            .help(help)
            .keyLED(led)
    }
}

/// Key icon that swaps in place when the state changes it (play/pause, repeat/repeat one).
struct KeySymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .contentTransition(.symbolEffect(.replace))
            .motion(Motion.state, value: name)
    }
}
