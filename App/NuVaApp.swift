import SwiftUI

@main
struct NuVaApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
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

        MenuBarExtra {
            MenuBarPlayer()
                .environment(model)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Fechar a janela não sai da app: a música continua e a NuVa fica na barra de menus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Atalhos do README. Enter e ⌘Enter vivem nas listas (dependem da seleção).
struct NuVaCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Adicionar pasta…") { model.addFolder() }
                .keyboardShortcut("o")
            Button("Adicionar Jellyfin…") { model.addJellyfin() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            Button("Player com playlist") { model.windowMode = .player }
                .keyboardShortcut("1")
            Button("Com navegador") { model.windowMode = .browser }
                .keyboardShortcut("2")
            Button("Compacto") { model.windowMode = .compact }
                .keyboardShortcut("3")
            Button(model.windowMode == .browser ? String(localized: "Esconder pastas") : String(localized: "Mostrar pastas")) { model.toggleBrowser() }
                .keyboardShortcut("b")
        }
        CommandMenu("Controlos") {
            Button(model.player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar")) { model.playOrBrowse() }
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
            Button(model.player.shuffle ? String(localized: "Desligar aleatório") : String(localized: "Aleatório")) { model.player.shuffle.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Ir para a faixa atual") {
                NotificationCenter.default.post(name: .revealCurrentTrack, object: nil)
            }
            .keyboardShortcut("l")
        }
    }
}
