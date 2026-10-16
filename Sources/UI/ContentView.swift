import SwiftUI

/// A janela escolhe o conteúdo pelo modo: player (360 × 480) ou com navegador (720 × 480).
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if model.windowMode == .browser {
                BrowserView()
                    .padding([.leading, .vertical], Space.s4)
                    .frame(width: 360)
            }
            PlayerView()
                .frame(width: 360)
        }
        .frame(width: model.windowMode == .browser ? 720 : 360, height: 480)
        .background(Color.surface0)
        .sheet(isPresented: $model.showingJellyfinLogin) {
            JellyfinLoginView()
        }
    }
}
