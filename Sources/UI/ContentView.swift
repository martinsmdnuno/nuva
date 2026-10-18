import SwiftUI

/// A janela escolhe o conteúdo pelo modo: player (360 × 480) ou com navegador (720 × 480).
/// Tudo no mesmo plano; o navegador separa-se do player por uma divisória vertical.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if model.windowMode == .browser {
                BrowserView()
                    .padding(Space.s4)
                    .frame(width: 359)
                Rectangle().fill(Color.line).frame(width: 1).padding(.vertical, Space.s4)
            }
            PlayerView()
                .frame(width: 360)
        }
        .frame(width: model.windowMode == .browser ? 720 : 360, height: 480)
        .background(Color.surface0)
        .sheet(isPresented: $model.showingJellyfinLogin) {
            JellyfinLoginView()
        }
        // Com a janela fechada, a NuVa sai do Dock e fica só na barra de menus.
        .onAppear { DockPresence.show(true) }
        .onDisappear { DockPresence.show(false) }
    }
}
