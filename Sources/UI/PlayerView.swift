import SwiftUI

/// "Player with queue" (360 × 480 or taller): display with position, keys, volume, queue.
/// In compact mode the queue goes away, leaving only the header with the "pastas" and "fila" labels.
/// Everything on the chassis plane; zones are separated by space.
struct PlayerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            DisplayView(allowsArtwork: model.windowMode != .compact)
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
