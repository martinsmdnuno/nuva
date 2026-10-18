import AppKit
import SwiftUI

/// Barra fina de posição/volume: calha e parte percorrida de 2px.
/// Área clicável de 16px; cabeça (traço de 2 × 10px) só no hover ou a arrastar.
struct BarSlider: View {
    /// 0...1
    var value: Double
    var onChange: (Double) -> Void
    /// Setas do teclado com foco: -1 ou +1.
    var onStep: (Int) -> Void
    /// Texto do tooltip no ponto do hover (0...1), ou nil para não mostrar.
    var hoverText: ((Double) -> String)?
    var trackColor = Color.track
    var fillColor = Color.fill

    @State private var hover: Double?
    @State private var dragging = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let v = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(trackColor)
                    .frame(height: Size.bar)
                Rectangle()
                    .fill(fillColor)
                    .frame(width: width * v, height: Size.bar)
                if hover != nil || dragging {
                    Rectangle()
                        .fill(fillColor)
                        .frame(width: 2, height: 10)
                        .offset(x: min(max(width * v - 1, 0), width - 2))
                }
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hover = min(max(p.x / width, 0), 1)
                case .ended: hover = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        onChange(min(max(g.location.x / width, 0), 1))
                    }
                    .onEnded { _ in dragging = false }
            )
            .overlay(alignment: .topLeading) {
                if let hover, let text = hoverText?(hover) {
                    Text(text)
                        .font(.dsDuration)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Space.s1)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.line))
                        .fixedSize()
                        .offset(x: min(max(width * hover - 20, 0), width - 40), y: -20)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 16)
        // Como as teclas: só no ciclo de foco com o acesso total pelo teclado,
        // para o foco inicial da janela ir para a fila e não para a barra.
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { onStep(-1); return .handled }
        .onKeyPress(.rightArrow) { onStep(1); return .handled }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: Radius.sm + 2)
                    .strokeBorder(Color.focus, lineWidth: 2)
                    .padding(-2)
            }
        }
    }
}

/// Barra de posição da faixa atual, dentro do display. Setas: 5 segundos.
struct ProgressBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let d = player.duration
        BarSlider(
            value: d > 0 ? player.currentTime / d : 0,
            onChange: { if d > 0 { player.seek(to: $0 * d) } },
            onStep: { player.skip(by: Double($0) * 5) },
            hoverText: d > 0 ? { TimeFormat.display($0 * d) } : nil,
            trackColor: .displayTrack,
            fillColor: .displayInk
        )
        .help("Posição")
    }
}

/// Volume da app (ou do destino AirPlay), com escala impressa de 0 a 10. ⌘↑ ⌘↓ e scroll mudam 5%.
struct VolumeControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let player = model.player
        HStack(alignment: .top, spacing: Space.s3) {
            Text("volume").legend()
                .frame(height: 16)
            VStack(spacing: 0) {
                BarSlider(
                    value: Double(player.volume),
                    onChange: { player.volume = Float($0) },
                    onStep: { player.changeVolume(by: Float($0) * 0.05) },
                    hoverText: nil
                )
                VolumeScale()
            }
        }
        .background {
            if !isSnapshot {
                ScrollWheelReader { delta in player.changeVolume(by: delta > 0 ? 0.05 : -0.05) }
            }
        }
        .help("Volume \(Int((player.volume * 100).rounded()))% ⌘↑ ⌘↓")
    }
}

/// Escala impressa por baixo do volume: 11 traços, 0, 5 e 10 numerados.
private struct VolumeScale: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0...10, id: \.self) { i in
                    Rectangle()
                        .fill(i % 5 == 0 ? Color.inkMuted : Color.line)
                        .frame(width: 1, height: i % 5 == 0 ? 5 : 3)
                    if i < 10 { Spacer(minLength: 0) }
                }
            }
            HStack {
                Text("0")
                Spacer()
                Text("5")
                Spacer()
                Text("10")
            }
            .font(Typography.mono(9, .regular))
            .foregroundStyle(Color.inkMuted)
        }
    }
}

/// Lê o scroll do rato por cima da vista, sem roubar cliques.
struct ScrollWheelReader: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onScroll = onScroll
    }

    final class ReaderView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      event.scrollingDeltaY != 0 else { return event }
                self.onScroll?(event.scrollingDeltaY)
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
