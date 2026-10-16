import SwiftUI

/// Linha de lista: pastas no navegador e faixas na fila.
struct ListRow: View {
    enum Leading {
        case folder
        case number(Int)
    }

    let leading: Leading
    let name: String
    var trailing: String = ""
    /// Duração em `duration` (mono) ou contagem em `caption`.
    var trailingIsDuration = true
    var isSelected = false
    var isPlaying = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.s2) {
            Group {
                switch leading {
                case .folder:
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkMuted)
                case .number(let n):
                    Text("\(n)")
                        .font(.dsDuration)
                        .foregroundStyle(isPlaying ? Color.signal : Color.inkMuted)
                }
            }
            .frame(width: 22, alignment: .trailing)

            Text(name)
                .font(.dsBody)
                .foregroundStyle(isPlaying ? Color.signal : Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !trailing.isEmpty {
                Text(trailing)
                    .font(trailingIsDuration ? .dsDuration : .dsCaption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(height: Size.row)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surface2)
            } else if hovering {
                Rectangle().fill(Color.surface0)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(name)
    }
}
