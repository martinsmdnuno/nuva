import AppKit
import SwiftUI

/// Thin position bar: 2px track and filled part.
/// 16px hit area; thumb (2 × 10px line) only on hover or while dragging.
struct BarSlider: View {
    /// 0...1
    var value: Double
    var onChange: (Double) -> Void
    /// Arrow keys when focused: -1 or +1.
    var onStep: (Int) -> Void
    /// Tooltip text at the hover point (0...1), or nil to hide it.
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
                Rectangle()
                    .fill(fillColor)
                    .frame(width: 2, height: 10)
                    .offset(x: min(max(width * v - 1, 0), width - 2))
                    .opacity(hover != nil || dragging ? 1 : 0)
                    .motion(Motion.hover, value: hover != nil || dragging)
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
        // Like the keys: only in the focus loop with full keyboard access,
        // so the window's initial focus goes to the queue and not the bar.
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

/// Position bar for the current track, inside the display. Arrows: 5 seconds.
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

/// Reads mouse scroll over the view without stealing clicks.
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
