import SwiftUI

/// List row: folders in the browser and tracks in the queue. No dividers between rows.
struct ListRow: View {
    enum Leading {
        case folder
        /// Track: LED lit while playing.
        case track
        case symbol(String)
    }

    let leading: Leading
    let name: String
    var trailing: String = ""
    /// Duration in `duration` (mono) or count in `caption`.
    var trailingIsDuration = true
    var isSelected = false
    var isPlaying = false
    /// Source in error: name and icon in `danger`.
    var isError = false
    /// Tooltip: the full name, with extension.
    var help: String?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Group {
                switch leading {
                case .folder:
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkMuted)
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? Color.danger : Color.inkMuted)
                case .track:
                    LED(isOn: true)
                        .opacity(isPlaying ? 1 : 0)
                        .motion(isPlaying ? Motion.ledOn : Motion.ledOff, value: isPlaying)
                }
            }
            .frame(width: 12)

            Text(name)
                .font(.dsBody)
                .foregroundStyle(isError ? Color.danger : isPlaying ? Color.signal : Color.ink)
                .motion(Motion.state, value: isPlaying)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !trailing.isEmpty {
                Text(trailing)
                    .font(trailingIsDuration ? .dsDuration : .dsCaption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .padding(.horizontal, Space.s2)
        .frame(height: Size.row)
        .background {
            // Selection snaps (it follows the keyboard); hover fades.
            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surface1)
                .opacity(hovering && !isSelected ? 1 : 0)
                .motion(Motion.hover, value: hovering)
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surface2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(help ?? name)
    }
}
