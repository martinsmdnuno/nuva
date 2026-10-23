import SwiftUI

/// The whole device: display with position, keys, volume, and below them the queue or the folders
/// (⌘B swaps them). In compact mode neither, leaving only the header with the "pastas" and "fila" labels.
/// Everything on the chassis plane; zones are separated by space.
struct PlayerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            DisplayView(allowsArtwork: model.windowMode != .compact, opensArtworkFix: true)
            ControlBar()
                .padding(.top, Space.s4)
            VolumeControl()
                .padding(.top, Space.s3)
            QueueHeader()
                .padding(.top, Space.s4)
            Group {
                switch model.windowMode {
                case .player: QueueList().transition(.opacity)
                case .browser: BrowserView().transition(.opacity)
                case .compact: EmptyView()
                }
            }
            .padding(.top, Space.s1 + 2)
            .motion(Motion.state, value: model.windowMode == .browser)
        }
        .padding(Space.s4)
    }
}
