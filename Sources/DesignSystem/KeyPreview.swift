import SwiftUI

/// Pré-visualização do design system: todas as teclas, letra e cores.
struct KeyPreview: View {
    @State private var repeatOn = true
    @State private var shuffleOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
                section("Transporte") {
                    HStack(spacing: Space.s1) {
                        key("backward.end", .md, "Anterior ⌘←")
                        key("play.fill", .lg, "Tocar Espaço")
                        key("forward.end", .md, "Seguinte ⌘→")
                        key("stop", .md, "Parar")
                    }
                }
                section("Secundárias") {
                    HStack(spacing: Space.s1) {
                        Button { repeatOn.toggle() } label: { Image(systemName: "repeat") }
                            .buttonStyle(.key(.sm, isOn: repeatOn)).keyFocus().help("Repetir")
                        Button { shuffleOn.toggle() } label: { Image(systemName: "shuffle") }
                            .buttonStyle(.key(.sm, isOn: shuffleOn)).keyFocus().help("Aleatório")
                        key("airplayaudio", .sm, "AirPlay")
                    }
                }
                section("Texto") {
                    HStack(spacing: Space.s1) {
                        Button("Cancelar") {}.buttonStyle(.keyText).keyFocus()
                        Button("Adicionar fonte") {}.buttonStyle(.keyText).keyFocus()
                    }
                }
                section("Letra") {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("01:23").font(.dsDisplayTime)
                        Text("FLAC 24/96").font(.dsDisplayMeta)
                        Text("Faixa de exemplo").font(.dsTitle)
                        Text("02 Remix.flac").font(.dsBody)
                        Text("Adicionar fonte").font(.dsLabel)
                        Text("12 faixas").font(.dsCaption)
                        Text("4:05").font(.dsDuration)
                    }
                    .foregroundStyle(Color.ink)
                }
                section("Cores") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: Space.s1)], spacing: Space.s1) {
                        ForEach(swatches, id: \.self) { name in
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color(name))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.line))
                                .frame(height: 28)
                                .help(name)
                        }
                    }
                }
            }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface1)
    }

    private let swatches = [
        "surface-0", "surface-1", "surface-2", "display", "display-ink", "display-muted",
        "ink", "ink-muted", "line", "key-face", "key-face-pressed", "key-edge",
        "track", "fill", "signal", "danger", "focus",
    ]

    private func key(_ symbol: String, _ size: KeyButtonStyle.KeySize, _ help: String) -> some View {
        Button {} label: { Image(systemName: symbol) }
            .buttonStyle(.key(size))
            .keyFocus()
            .help(help)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.dsLabel).foregroundStyle(Color.inkMuted)
            content()
        }
    }
}

#Preview("Chumbo") { KeyPreview().frame(width: 360, height: 480).preferredColorScheme(.dark) }
#Preview("Alumínio") { KeyPreview().frame(width: 360, height: 480).preferredColorScheme(.light) }
