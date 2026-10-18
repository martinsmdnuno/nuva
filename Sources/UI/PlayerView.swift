import SwiftUI

/// "Player com playlist" (360 × 480): display com a posição, teclas, volume, fila.
/// Tudo no mesmo plano do chassis; as zonas separam-se por espaço.
struct PlayerView: View {
    var body: some View {
        VStack(spacing: 0) {
            DisplayView()
            ControlBar()
                .padding(.top, Space.s4)
            VolumeControl()
                .padding(.top, Space.s3)
            QueueList()
                .padding(.top, Space.s4)
        }
        .padding(Space.s4)
    }
}
