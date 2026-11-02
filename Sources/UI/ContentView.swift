import AppKit
import SwiftUI

/// One device in every mode: display, keys, volume, and below them the queue or the folders,
/// or neither in compact mode (height from content). The width is free from 360 to 480: keys keep
/// their size and the space between groups grows, while the display and the lists stretch.
/// With the queue or the folders the height is free too (minimum 480), to see a whole album.
/// Title bar zoom stretches the window to the screen height. Both sizes are remembered.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Last height with the queue or the folders, across modes and launches.
    @AppStorage("listHeight") private var listHeight = Double(Self.minHeight)
    /// Last width, in every mode.
    @AppStorage("playerWidth") private var windowWidth = Double(Self.minWidth)
    /// Height to restore when leaving compact mode (saved on entry, before the window shrinks).
    @State private var heightToRestore: Double?
    @State private var window: NSWindow?

    static let minHeight: CGFloat = 540
    static let minWidth: CGFloat = 360
    static let maxWidth: CGFloat = 480

    var body: some View {
        @Bindable var model = model
        let compact = model.windowMode == .compact
        PlayerView()
        // A new skin or font set rebuilds the content, so every colour and font is resolved again.
        .id(SkinStore.shared.renderID)
        .frame(minWidth: Self.minWidth, idealWidth: Self.minWidth, maxWidth: Self.maxWidth)
        .frame(
            minHeight: compact ? nil : Self.minHeight,
            idealHeight: compact ? nil : Self.minHeight,
            maxHeight: compact ? nil : .infinity
        )
        // In compact mode the height follows the content, no resize.
        .fixedSize(horizontal: false, vertical: compact)
        .background(Color.surface0)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            if size.width >= Self.minWidth { windowWidth = Double(size.width) }
            if model.windowMode != .compact, size.height >= Self.minHeight { listHeight = Double(size.height) }
        }
        .background(WindowReader { window = $0 })
        .onChange(of: window) { _, window in
            if let window { setSize(width: windowWidth, height: compact ? nil : listHeight, of: window) }
        }
        .onChange(of: model.windowMode) { old, new in
            if new == .compact {
                heightToRestore = listHeight
            } else if old == .compact, let window {
                let target = heightToRestore ?? listHeight
                // After the window adjusts to the new content.
                DispatchQueue.main.async { setSize(width: nil, height: target, of: window) }
            }
        }
        .sheet(isPresented: $model.showingJellyfinLogin) {
            JellyfinLoginView()
        }
        .sheet(item: $model.fixingArtwork) { entry in
            ArtworkFixView(entry: entry, guess: model.artworkResolver.query(for: entry))
        }
        // With the window closed, NuVa leaves the Dock and stays only in the menu bar.
        .onAppear {
            DockPresence.show(true)
            model.isMainWindowOpen = true
        }
        .onDisappear {
            DockPresence.show(false)
            model.isMainWindowOpen = false
        }
    }

    /// Changes the content size (nil keeps that side) while keeping the window's top left in place.
    private func setSize(width: Double?, height: Double?, of window: NSWindow) {
        let visible = window.screen.map { window.contentRect(forFrameRect: $0.visibleFrame).size }
        var frame = window.frame
        let content = window.contentRect(forFrameRect: frame).size
        let dw = width.map { min(max(CGFloat($0), Self.minWidth), min(Self.maxWidth, visible?.width ?? .infinity)) - content.width } ?? 0
        let dh = height.map { min(max(CGFloat($0), Self.minHeight), visible?.height ?? .infinity) - content.height } ?? 0
        guard abs(dw) > 0.5 || abs(dh) > 0.5 else { return }
        frame.origin.y -= dh
        frame.size.width += dw
        frame.size.height += dh
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
