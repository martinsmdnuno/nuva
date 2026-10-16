import AppKit
import SwiftUI

/// Barra fina de progresso/volume: calha `track`, parte percorrida `fill`.
/// Área clicável de 16px; cabeça de 10px só no hover ou a arrastar.
struct BarSlider: View {
    /// 0...1
    var value: Double
    var onChange: (Double) -> Void
    /// Setas do teclado com foco: -1 ou +1.
    var onStep: (Int) -> Void
    /// Texto do tooltip no ponto do hover (0...1), ou nil para não mostrar.
    var hoverText: ((Double) -> String)?

    @State private var hover: Double?
    @State private var dragging = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let v = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.track)
                    .frame(height: Size.bar)
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(Color.fill)
                    .frame(width: width * v, height: Size.bar)
                if hover != nil || dragging {
                    Circle()
                        .fill(Color.fill)
                        .frame(width: 10, height: 10)
                        .offset(x: width * v - 5)
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

/// Barra de progresso da faixa atual. Setas: 5 segundos.
struct ProgressBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let d = player.duration
        BarSlider(
            value: d > 0 ? player.currentTime / d : 0,
            onChange: { if d > 0 { player.seek(to: $0 * d) } },
            onStep: { player.skip(by: Double($0) * 5) },
            hoverText: d > 0 ? { TimeFormat.display($0 * d) } : nil
        )
        .help("Posição")
    }
}

/// Volume da app (ou do destino AirPlay). ⌘↑ ⌘↓ e scroll mudam 5%.
struct VolumeControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let player = model.player
        HStack(spacing: Space.s1) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 16)
            BarSlider(
                value: Double(player.volume),
                onChange: { player.volume = Float($0) },
                onStep: { player.changeVolume(by: Float($0) * 0.05) },
                hoverText: nil
            )
            .frame(width: 80)
        }
        .background {
            if !isSnapshot {
                ScrollWheelReader { delta in player.changeVolume(by: delta > 0 ? 0.05 : -0.05) }
            }
        }
        .help("Volume \(Int((player.volume * 100).rounded()))% ⌘↑ ⌘↓")
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
