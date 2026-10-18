import AppKit
import SwiftUI

/// A janela escolhe o conteúdo pelo modo: player (360 de largura), com navegador (720)
/// ou compacto (360, sem fila, altura pelo conteúdo).
/// No player e no navegador a altura é livre (mínimo 480), para ver um álbum inteiro;
/// a largura é fixa. O zoom da barra de título estica a janela até à altura do ecrã.
/// Tudo no mesmo plano; o navegador separa-se do player por uma divisória vertical.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Última altura do player ou do navegador, entre modos e entre arranques.
    @AppStorage("listHeight") private var listHeight = Double(Self.minHeight)
    /// Altura a repor ao sair do compacto (guardada ao entrar, antes de a janela encolher).
    @State private var heightToRestore: Double?
    @State private var window: NSWindow?

    static let minHeight: CGFloat = 480

    var body: some View {
        @Bindable var model = model
        let compact = model.windowMode == .compact
        HStack(spacing: 0) {
            if model.windowMode == .browser {
                BrowserView()
                    .padding(Space.s4)
                    .frame(width: 359)
                Rectangle().fill(Color.line).frame(width: 1).padding(.vertical, Space.s4)
            }
            PlayerView()
                .frame(width: 360)
        }
        .frame(width: model.windowMode == .browser ? 720 : 360)
        .frame(
            minHeight: compact ? nil : Self.minHeight,
            idealHeight: compact ? nil : Self.minHeight,
            maxHeight: compact ? nil : .infinity
        )
        // No compacto a altura é a do conteúdo, sem resize.
        .fixedSize(horizontal: false, vertical: compact)
        .background(Color.surface0)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            if model.windowMode != .compact, height >= Self.minHeight { listHeight = Double(height) }
        }
        .background(WindowReader { window = $0 })
        .onChange(of: window) { _, window in
            if let window, !compact { setHeight(listHeight, of: window) }
        }
        .onChange(of: model.windowMode) { old, new in
            if new == .compact {
                heightToRestore = listHeight
            } else if old == .compact, let window {
                let target = heightToRestore ?? listHeight
                // Depois de a janela se ajustar ao novo conteúdo.
                DispatchQueue.main.async { setHeight(target, of: window) }
            }
        }
        .sheet(isPresented: $model.showingJellyfinLogin) {
            JellyfinLoginView()
        }
        // Com a janela fechada, a NuVa sai do Dock e fica só na barra de menus.
        .onAppear { DockPresence.show(true) }
        .onDisappear { DockPresence.show(false) }
    }

    /// Muda a altura do conteúdo mantendo o topo da janela no sítio.
    private func setHeight(_ height: Double, of window: NSWindow) {
        let maxHeight = window.screen.map { window.contentRect(forFrameRect: $0.visibleFrame).height } ?? .infinity
        let target = min(max(CGFloat(height), Self.minHeight), maxHeight)
        var frame = window.frame
        let delta = target - window.contentRect(forFrameRect: frame).height
        guard abs(delta) > 0.5 else { return }
        frame.origin.y -= delta
        frame.size.height += delta
        window.setFrame(frame, display: true, animate: true)
    }
}

/// Dá acesso à NSWindow que contém a vista.
private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [onWindow] in onWindow?(window) }
        }
    }
}
