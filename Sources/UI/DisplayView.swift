import SwiftUI

/// O ecrã do aparelho. Sempre escuro, nos dois temas.
struct DisplayView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showsRemaining") private var showsRemaining = false

    var body: some View {
        let player = model.player
        let entry = player.current?.entry

        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Circle()
                    .fill(player.isPlaying ? Color.signal : Color.displayMuted.opacity(0.25))
                    .frame(width: 6, height: 6)
                Text(player.formatLabel)
                Spacer(minLength: Space.s2)
                Text(model.currentSourceLabel)
            }
            .font(.dsDisplayMeta)
            .foregroundStyle(Color.displayMuted)
            .frame(height: 14)

            Text(entry?.title ?? "Sem faixa")
                .font(.dsTitle)
                .foregroundStyle(entry == nil ? Color.displayMuted : Color.displayInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(entry?.name ?? "")
                .frame(height: 20)

            HStack(spacing: Space.s2) {
                Text(entry?.folderName ?? "Escolher uma pasta para tocar")
                    .font(.dsCaption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry?.parentPath ?? "")
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(model.output.label)
                    .font(.dsDisplayMeta)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.output.detail)
            }
            .foregroundStyle(Color.displayMuted)

            HStack(alignment: .lastTextBaseline) {
                Text(timeText(player))
                    .font(.dsDisplayTime)
                    .foregroundStyle(Color.displayInk)
                    .contentShape(Rectangle())
                    .onTapGesture { showsRemaining.toggle() }
                    .help(showsRemaining ? "Mostrar tempo decorrido" : "Mostrar tempo restante")
                Spacer()
                Text(TimeFormat.display(player.duration))
                    .font(.dsDisplayMeta)
                    .foregroundStyle(Color.displayMuted)
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.display, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func timeText(_ player: PlayerController) -> String {
        guard showsRemaining, player.duration > 0 else { return TimeFormat.display(player.currentTime) }
        return "-" + TimeFormat.display(player.duration - player.currentTime)
    }
}
