import SwiftUI

/// Linha de lista: pastas no navegador e faixas na fila. Sem divisórias entre linhas.
struct ListRow: View {
    enum Leading {
        case folder
        /// Faixa: LED aceso quando está a tocar.
        case track
        case symbol(String)
    }

    let leading: Leading
    let name: String
    var trailing: String = ""
    /// Duração em `duration` (mono) ou contagem em `caption`.
    var trailingIsDuration = true
    var isSelected = false
    var isPlaying = false
    /// Fonte em erro: nome e ícone em `danger`.
    var isError = false
    /// Tooltip: o nome completo, com extensão.
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
                    LED(isOn: true).opacity(isPlaying ? 1 : 0)
                }
            }
            .frame(width: 12)

            Text(name)
                .font(.dsBody)
                .foregroundStyle(isError ? Color.danger : isPlaying ? Color.signal : Color.ink)
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
            if isSelected {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surface2)
            } else if hovering {
                RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surface1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(help ?? name)
    }
}
