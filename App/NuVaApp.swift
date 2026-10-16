import SwiftUI

@main
struct NuVaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 480)
    }
}
