import SwiftUI

/// "Player com playlist" (360 × 480): display, progresso, volume e equalizador, controlos, fila.
struct PlayerView: View {
    var body: some View {
        VStack(spacing: 0) {
            DisplayView()
            HStack(spacing: Space.s4) {
                ProgressBar()
                VolumeControl()
                EqualizerKey()
            }
            .padding(.vertical, Space.s2)
            VStack(spacing: 0) {
                ControlBar()
                    .padding(Space.s3)
                Rectangle().fill(Color.line).frame(height: 1)
                QueueList()
            }
            .background(Color.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(Space.s4)
    }
}
