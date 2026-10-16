import SwiftUI

@main
struct NuVaApp: App {
    @State private var model: AppModel

    init() {
        Typography.registerFonts()
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Player com playlist") { model.windowMode = .player }
                    .keyboardShortcut("1")
                Button("Com navegador") { model.windowMode = .browser }
                    .keyboardShortcut("2")
            }
        }
    }
}
