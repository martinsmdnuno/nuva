import SwiftUI

/// "Player com playlist" (360 × 480): display com a posição, teclas, volume, fila.
/// No compacto a fila sai e fica só o cabeçalho com as pistas "pastas" e "fila".
/// Tudo no mesmo plano do chassis; as zonas separam-se por espaço.
struct PlayerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            DisplayView()
            ControlBar()
                .padding(.top, Space.s4)
            VolumeControl()
                .padding(.top, Space.s3)
            QueueHeader()
                .padding(.top, Space.s4)
            if model.windowMode != .compact {
                QueueList()
                    .padding(.top, Space.s1 + 2)
            }
        }
        .padding(Space.s4)
    }
}
