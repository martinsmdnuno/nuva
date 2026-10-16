import SwiftUI

/// Tecla do equalizador, ao lado do volume. Abre o painel num popover.
struct EqualizerKey: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        let eq = model.player.equalizer
        Button { showing.toggle() } label: { Image(systemName: "slider.vertical.3") }
            .buttonStyle(.key(.sm, isOn: eq.enabled))
            .keyFocus()
            .help(eq.enabled ? "Equalizador: \(eq.presetName)" : "Equalizador desligado")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                EqualizerPanel(eq: eq)
            }
    }
}

/// Presets por cima, 10 bandas de -12 a +12 dB por baixo.
struct EqualizerPanel: View {
    @Bindable var eq: Equalizer

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Equalizador")
                    .font(.dsLabel)
                    .foregroundStyle(Color.ink)
                Text(eq.presetName)
                    .font(.dsCaption)
                    .foregroundStyle(Color.inkMuted)
                Spacer()
                Button(eq.enabled ? "Ligado" : "Desligado") { eq.enabled.toggle() }
                    .buttonStyle(.keyText(isOn: eq.enabled))
                    .keyFocus()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s1), count: 4), spacing: Space.s1) {
                ForEach(Equalizer.presets) { preset in
                    Button { eq.apply(preset) } label: {
                        Text(preset.name).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.keyText(isOn: eq.enabled && eq.presetName == preset.name))
                    .keyFocus()
                }
            }
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .trailing) {
                    Text("+12")
                    Spacer()
                    Text("0")
                    Spacer()
                    Text("-12")
                }
                .font(.dsDisplayMeta)
                .foregroundStyle(Color.inkMuted)
                .frame(height: 120)
                ForEach(Equalizer.labels.indices, id: \.self) { band in
                    BandSlider(
                        value: eq.gains[band], label: Equalizer.labels[band],
                        onChange: { eq.setGain(band, $0) })
                }
            }
            .opacity(eq.enabled ? 1 : 0.5)
        }
        .padding(Space.s4)
        .frame(width: 380)
        .background(Color.surface1)
    }
}

/// Uma banda: calha vertical com o zero ao meio. Duplo clique volta a 0 dB.
private struct BandSlider: View {
    let value: Float
    let label: String
    let onChange: (Float) -> Void
    @State private var active = false

    var body: some View {
        VStack(spacing: Space.s1) {
            GeometryReader { geo in
                let h = geo.size.height
                let range = Equalizer.range
                let y = { (v: Float) in h * CGFloat((range.upperBound - v) / (range.upperBound - range.lowerBound)) }
                let mid = y(0)
                let pos = y(value)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.track)
                        .frame(width: Size.bar)
                    Rectangle()
                        .fill(Color.line)
                        .frame(width: 12, height: 1)
                        .offset(y: mid)
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(Color.fill)
                        .frame(width: Size.bar, height: abs(pos - mid))
                        .offset(y: min(pos, mid))
                    Circle()
                        .fill(Color.fill)
                        .frame(width: active ? 12 : 10, height: active ? 12 : 10)
                        .offset(y: pos - (active ? 6 : 5))
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
