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
        .defaultSize(width: 360, height: 480)
    }
}
