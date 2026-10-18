import AppKit
import SwiftUI

/// The window picks its content by mode: player (360 wide), with browser (720)
/// or compact (360, no queue, height from content).
/// In player and browser modes the height is free (minimum 480), to see a whole album;
/// the width is fixed. Title bar zoom stretches the window to the screen height.
/// Everything on one plane; the browser is separated from the player by a vertical divider.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Last player or browser height, across modes and launches.
    @AppStorage("listHeight") private var listHeight = Double(Self.minHeight)
    /// Height to restore when leaving compact mode (saved on entry, before the window shrinks).
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
        // A new skin rebuilds the content, so every colour is resolved again.
        .id(SkinStore.shared.current.id)
        .frame(width: model.windowMode == .browser ? 720 : 360)
        .frame(
            minHeight: compact ? nil : Self.minHeight,
            idealHeight: compact ? nil : Self.minHeight,
            maxHeight: compact ? nil : .infinity
        )
        // In compact mode the height follows the content, no resize.
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
                // After the window adjusts to the new content.
                DispatchQueue.main.async { setHeight(target, of: window) }
            }
        }
        .sheet(isPresented: $model.showingJellyfinLogin) {
            JellyfinLoginView()
        }
        // With the window closed, NuVa leaves the Dock and stays only in the menu bar.
        .onAppear { DockPresence.show(true) }
        .onDisappear { DockPresence.show(false) }
    }

    /// Changes the content height while keeping the window's top in place.
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

/// Gives access to the NSWindow containing the view.
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
