import SwiftUI

/// App volume (or AirPlay destination volume) as a knob, the height of a key, with a printed
/// 0 to 10 scale around it. Drag up or down, scroll, or the arrows when focused; ⌘↑ ⌘↓ change 5%.
/// The pointer follows the value directly, like the position bar: it's the readout.
struct VolumeKnob: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var dragStart: Float?
    @FocusState private var focused: Bool

    /// The pointer turns 270°, from 7 to 5 o'clock.
    private static let sweep = 270.0
    /// Points of vertical drag for the whole range.
    private static let travel: Float = 160

    var body: some View {
        let player = model.player
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0...10 {
                    let major = i % 5 == 0
                    let a = Self.angle(Double(i) / 10)
                    var tick = Path()
                    tick.move(to: point(c, a, 15.5))
                    tick.addLine(to: point(c, a, major ? 18 : 17))
                    context.stroke(tick, with: .color(major ? .inkMuted : .line), lineWidth: 1)
                }
            }
            Circle()
                .fill(Color.keyMode)
                .frame(width: 26, height: 26)
            // Pointer: a line from the centre towards the rim.
            Rectangle()
                .fill(Color.keyModeInk)
                .frame(width: Size.bar, height: 9)
                .offset(y: -6.5)
                .rotationEffect(.degrees(Self.angle(Double(player.volume))))
        }
        .frame(width: Size.key, height: Size.key)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let start = dragStart ?? player.volume
                    dragStart = start
                    player.volume = min(max(start - Float(g.translation.height) / Self.travel, 0), 1)
                }
                .onEnded { _ in dragStart = nil }
        )
        .background {
            if !isSnapshot {
                ScrollWheelReader { delta in player.changeVolume(by: delta > 0 ? 0.05 : -0.05) }
            }
        }
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { player.changeVolume(by: 0.05); return .handled }
        .onKeyPress(.rightArrow) { player.changeVolume(by: 0.05); return .handled }
        .onKeyPress(.downArrow) { player.changeVolume(by: -0.05); return .handled }
        .onKeyPress(.leftArrow) { player.changeVolume(by: -0.05); return .handled }
        .overlay {
            if focused {
                Circle().strokeBorder(Color.focus, lineWidth: 2).padding(-2)
            }
        }
        .help("Volume \(Int((player.volume * 100).rounded()))% ⌘↑ ⌘↓")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((player.volume * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.changeVolume(by: 0.05)
            case .decrement: player.changeVolume(by: -0.05)
            @unknown default: break
            }
        }
    }

    /// Volume as a scale reading, 0 to 10, for the legend.
    static func reading(_ volume: Float) -> String {
        let tenths = Int((volume * 100).rounded()) / 10
        return "\(tenths)"
    }

    /// Degrees from 12 o'clock for a value 0...1.
    private static func angle(_ value: Double) -> Double {
        -sweep / 2 + sweep * min(max(value, 0), 1)
    }

    private func point(_ c: CGPoint, _ degrees: Double, _ r: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
    }
}
