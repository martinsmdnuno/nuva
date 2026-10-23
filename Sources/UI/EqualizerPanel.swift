import SwiftUI

/// The equalizer on the display, beside the time: LED and preset ("EQ · Rock").
/// Clicking opens the panel, as does Controls ▸ Equalizer… (⌥⌘E) in the main window.
struct EqualizerControl: View {
    /// The main window's control answers the menu command; the mini player's keeps its own.
    var followsMenu = false
    @Environment(AppModel.self) private var model
    @State private var localShowing = false
    @State private var hover = false

    var body: some View {
        @Bindable var model = model
        let eq = model.player.equalizer
        let showing = followsMenu ? $model.showsEqualizer : $localShowing
        Button { showing.wrappedValue.toggle() } label: {
            HStack(spacing: Space.s1 + 2) {
                LED(isOn: eq.enabled)
                Text(verbatim: eq.enabled ? "EQ · \(Equalizer.displayName(eq.presetName))" : "EQ")
            }
            .font(.dsDisplayMeta)
            .foregroundStyle(hover ? Color.displayInk : Color.displayMuted)
            .motion(Motion.hover, value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hover = $0 }
        .help((eq.enabled
            ? String(localized: "Equalizador: \(Equalizer.displayName(eq.presetName))")
            : String(localized: "Equalizador desligado")) + " ⌥⌘E")
        .popover(isPresented: showing, arrowEdge: .bottom) {
            EqualizerPanel(eq: eq)
        }
    }
}

/// Switch with LED on top, presets as text with LED, 10 bands from -12 to +12 dB with a printed scale.
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
                            Text(Equalizer.displayName(preset.name).lowercased())
                                .font(.dsCaption)
                                .foregroundStyle(active ? Color.ink : Color.inkMuted)
                                .motion(Motion.hover, value: active)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Preset \(Equalizer.displayName(preset.name))"))
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
            .motion(Motion.state, value: eq.enabled)
            // A preset moves the faders like motorised ones; dragging stays direct.
            .motion(Motion.fader, value: eq.presetName)
        }
        .padding(Space.s4)
        .frame(width: 380)
        .background(Color.surface1)
    }

    /// Vertical position of a gain on the scale.
    static func y(_ gain: Float) -> CGFloat {
        let range = Equalizer.range
        return height * CGFloat((range.upperBound - gain) / (range.upperBound - range.lowerBound))
    }
}

/// Slide switch with LED. The text describes the state, not the action.
private struct PowerSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Space.s1 + 2) {
                LED(isOn: isOn)
                Text(isOn ? String(localized: "ligado") : String(localized: "desligado")).legend()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.surface0)
                    RoundedRectangle(cornerRadius: 1).fill(Color.keyFace)
                        .frame(width: 10, height: 10)
                        .padding(2)
                }
                .frame(width: 26, height: 14)
                .motion(Motion.state, value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? String(localized: "Desligar o equalizador") : String(localized: "Ligar o equalizador"))
    }
}

/// One band: printed scale behind, 2px track and fader cap. Double-click resets to 0 dB.
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
