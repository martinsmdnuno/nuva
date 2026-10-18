import SwiftUI

/// Design-system preview: all keys, type and colours.
struct KeyPreview: View {
    @State private var repeatOn = true
    @State private var shuffleOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
                section("Teclas") {
                    HStack(alignment: .bottom, spacing: Space.s1) {
                        key("backward.end", .transport, "Anterior ⌘←")
                        key("play.fill", .play, "Tocar Espaço")
                        key("forward.end", .transport, "Seguinte ⌘→")
                        Spacer().frame(width: Space.s4)
                        Button { repeatOn.toggle() } label: { Image(systemName: "repeat") }
                            .buttonStyle(.key(.mode)).keyFocus().help("Repetir").keyLED(repeatOn)
                        Button { shuffleOn.toggle() } label: { Image(systemName: "shuffle") }
                            .buttonStyle(.key(.mode)).keyFocus().help("Aleatório").keyLED(shuffleOn)
                    }
                }
                section("Texto") {
                    HStack(spacing: Space.s1) {
                        Button("Cancelar") {}.buttonStyle(.keyText).keyFocus()
                        Button("Adicionar pasta") {}.buttonStyle(.keyText).keyFocus()
                    }
                }
                section("Letra") {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("01:23").font(.dsDisplayTime)
                        Text("FLAC 24/96").font(.dsDisplayMeta)
                        Text("Faixa de exemplo").font(.dsTitle)
                        Text("02 Remix").font(.dsBody)
                        Text("Adicionar pasta").font(.dsLabel)
                        Text("12 faixas").font(.dsCaption)
                        Text("leitura · modo · saída").font(.dsLegend)
                        Text("4:05").font(.dsDuration)
                    }
                    .foregroundStyle(Color.ink)
                }
                section("Cores") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: Space.s1)], spacing: Space.s1) {
                        ForEach(swatches, id: \.self) { name in
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color(name))
                                .frame(height: 28)
                                .help(name)
                        }
                    }
                }
            }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface0)
    }

    private let swatches = [
        "surface-0", "surface-1", "surface-2", "display", "display-ink", "display-muted", "display-track",
        "ink", "ink-muted", "line", "key-face", "key-mode", "key-play", "key-ink", "key-mode-ink",
        "track", "fill", "led", "led-off", "signal", "danger", "focus",
    ]

    private func key(_ symbol: String, _ tone: KeyButtonStyle.Tone, _ help: String) -> some View {
        Button {} label: { Image(systemName: symbol) }
            .buttonStyle(.key(tone))
            .keyFocus()
            .help(help)
            .keyLED(nil)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title.lowercased()).legend()
            content()
        }
    }
}

#Preview("Chumbo") { KeyPreview().frame(width: 360, height: 480).preferredColorScheme(.dark) }
#Preview("Alumínio") { KeyPreview().frame(width: 360, height: 480).preferredColorScheme(.light) }
