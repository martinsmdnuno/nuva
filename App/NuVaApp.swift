import SwiftUI

@main
struct NuVaApp: App {
    @State private var model: AppModel

    init() {
        Typography.registerFonts()
        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif
        _model = State(initialValue: AppModel(systemIntegration: true))
    }

    var body: some Scene {
        Window("NuVa", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .commands { NuVaCommands(model: model) }
    }
}

/// Atalhos do README. Enter e ⌘Enter vivem nas listas (dependem da seleção).
struct NuVaCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Adicionar fonte…") {
                model.windowMode = .browser
                model.addSource()
            }
            .keyboardShortcut("o")
        }
        CommandGroup(after: .sidebar) {
            Button("Player com playlist") { model.windowMode = .player }
                .keyboardShortcut("1")
            Button("Com navegador") { model.windowMode = .browser }
                .keyboardShortcut("2")
        }
        CommandMenu("Controlos") {
            Button(model.player.isPlaying ? "Pausa" : "Tocar") { model.playOrBrowse() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Parar") { model.player.stop() }
                .keyboardShortcut(".")
            Button("Seguinte") { model.player.next() }
                .keyboardShortcut(.rightArrow)
            Button("Anterior") { model.player.previous() }
                .keyboardShortcut(.leftArrow)
            Divider()
            Button("Aumentar volume") { model.player.changeVolume(by: 0.05) }
                .keyboardShortcut(.upArrow)
            Button("Baixar volume") { model.player.changeVolume(by: -0.05) }
                .keyboardShortcut(.downArrow)
            Divider()
            Button("Repetir") { model.player.repeatMode = model.player.repeatMode.next }
                .keyboardShortcut("r")
            Button(model.player.shuffle ? "Desligar aleatório" : "Aleatório") { model.player.shuffle.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Ir para a faixa atual") {
                NotificationCenter.default.post(name: .revealCurrentTrack, object: nil)
            }
            .keyboardShortcut("l")
        }
    }
}
