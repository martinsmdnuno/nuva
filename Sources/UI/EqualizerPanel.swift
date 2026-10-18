import SwiftUI

/// Tecla do equalizador, ao lado do volume. Abre o painel num popover.
struct EqualizerKey: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        let eq = model.player.equalizer
        Button { showing.toggle() } label: { Image(systemName: "slider.vertical.3") }
            .buttonStyle(.key(.mode))
            .keyFocus()
            .help(eq.enabled ? "Equalizador: \(eq.presetName)" : "Equalizador desligado")
            .keyLED(eq.enabled)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                EqualizerPanel(eq: eq)
            }
    }
}

/// Interruptor com LED por cima, presets como texto com LED, 10 bandas de -12 a +12 dB com escala impressa.
struct EqualizerPanel: View {
    @Bindable var eq: Equalizer

    private static let marks: [Float] = [12, 6, 0, -6, -12]
    private static let height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("equalizador")
                    .font(.dsLabel)
                    .foregroundStyle(Color.ink)
                Spacer()
                PowerSwitch(isOn: $eq.enabled)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s1, alignment: .leading), count: 4),
                alignment: .leading, spacing: Space.s2
            ) {
                ForEach(Equalizer.presets) { preset in
                    let active = eq.enabled && eq.presetName == preset.name
                    Button { eq.apply(preset) } label: {
                        HStack(spacing: Space.s1 + 2) {
                            LED(isOn: active)
                            Text(preset.name.lowercased())
                                .font(.dsCaption)
                                .foregroundStyle(active ? Color.ink : Color.inkMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Preset \(preset.name)")
                }
            }
            HStack(alignment: .top, spacing: Space.s2) {
                ZStack(alignment: .topTrailing) {
                    ForEach(Self.marks, id: \.self) { mark in
                        Text(mark > 0 ? "+\(Int(mark))" : "\(Int(mark))")
                            .position(x: 14, y: Self.y(mark))
                    }
                }
                .font(.dsDisplayMeta)
                .foregroundStyle(Color.inkMuted)
                .frame(width: 28, height: Self.height)
                ForEach(Equalizer.labels.indices, id: \.self) { band in
                    BandSlider(
                        value: eq.gains[band], label: Equalizer.labels[band], marks: Self.marks, y: Self.y,
                        onChange: { eq.setGain(band, $0) })
                }
            }
            .opacity(eq.enabled ? 1 : 0.5)
        }
        .padding(Space.s4)
        .frame(width: 380)
        .background(Color.surface1)
    }

    /// Posição vertical de um ganho na escala.
    static func y(_ gain: Float) -> CGFloat {
        let range = Equalizer.range
        return height * CGFloat((range.upperBound - gain) / (range.upperBound - range.lowerBound))
    }
}

/// Interruptor deslizante com LED. O texto descreve o estado, não a ação.
private struct PowerSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Space.s1 + 2) {
                LED(isOn: isOn)
                Text(isOn ? "ligado" : "desligado").legend()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.surface0)
                    RoundedRectangle(cornerRadius: 1).fill(Color.keyFace)
                        .frame(width: 10, height: 10)
                        .padding(2)
                }
                .frame(width: 26, height: 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Desligar o equalizador" : "Ligar o equalizador")
    }
}

/// Uma banda: escala impressa por trás, calha de 2px e cursor de fader. Duplo clique volta a 0 dB.
private struct BandSlider: View {
    let value: Float
    let label: String
    let marks: [Float]
    let y: (Float) -> CGFloat
    let onChange: (Float) -> Void
    @State private var active = false

    var body: some View {
        VStack(spacing: Space.s1) {
            GeometryReader { geo in
                let h = geo.size.height
                let range = Equalizer.range
                ZStack(alignment: .top) {
                    ForEach(marks, id: \.self) { mark in
                        Rectangle()
                            .fill(mark == 0 ? Color.line : Color.surface2)
                            .frame(height: 1)
                            .offset(y: y(mark))
                    }
                    Rectangle()
                        .fill(Color.surface0)
                        .frame(width: Size.bar)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.keyFace)
                        .frame(width: 16, height: 8)
                        .overlay { Rectangle().fill(Color.keyInk.opacity(0.5)).frame(height: 1).padding(.horizontal, 2) }
                        .brightness(active ? 0.06 : 0)
                        .offset(y: y(value) - 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            active = true
                            let t = Float(min(max(g.location.y / h, 0), 1))
                            onChange(range.upperBound - t * (range.upperBound - range.lowerBound))
                        }
                        .onEnded { _ in active = false }
                )
                .onTapGesture(count: 2) { onChange(0) }
            }
            .frame(height: 120)
            Text(label)
                .font(.dsDisplayMeta)
                .foregroundStyle(Color.inkMuted)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .help("\(label) Hz \(value > 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(0...1)))) dB")
    }
}
