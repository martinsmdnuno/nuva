import AVKit
import SwiftUI

/// Where the sound goes, on the display ("→ AirPlay WiiM"). Clicking opens the native
/// AirPlay picker: an AVRoutePickerView sits, nearly transparent, over the text.
struct OutputControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var hover = false

    var body: some View {
        let output = model.output
        HStack(spacing: Space.s1) {
            Image(systemName: "airplayaudio")
                .font(.system(size: 9))
            Text(output.label.isEmpty ? "AirPlay" : output.label.replacingOccurrences(of: "→ ", with: ""))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.dsDisplayMeta)
        .foregroundStyle(hover ? Color.displayInk : Color.displayMuted)
        .motion(Motion.hover, value: hover)
        .contentShape(Rectangle())
        .overlay {
            if !isSnapshot {
                RoutePicker(player: model.player.avPlayer, toolTip: tooltip(output))
            }
        }
        .onHover { hover = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Escolher a saída"))
    }

    private func tooltip(_ output: OutputRoute) -> String {
        let choose = String(localized: "Escolher a saída")
        return output.detail.isEmpty ? choose : "\(output.detail)\n\(choose)"
    }
}

/// The native route picker, stretched over the output text and almost invisible,
/// so its own click opens the AirPlay menu in the right place.
private struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer
    let toolTip: String

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        // Fully transparent views still get clicks in AppKit, but keep a trace to be safe.
        view.alphaValue = 0.02
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
        view.toolTip = toolTip
    }
}
