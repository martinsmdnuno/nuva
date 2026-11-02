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

        Window("Termos e privacidade", id: "terms") {
            TermsView()
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: Binding(get: { !model.isMainWindowOpen }, set: { _ in })) {
            MenuBarPlayer()
                .environment(model)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Closing the window doesn't quit the app: the music keeps playing and NuVa stays in the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SkinStore.shared.applyAppearance()
        UpdateChecker.shared.checkAtLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Shortcuts from the README. Enter and ⌘Enter live in the lists (they depend on the selection).
struct NuVaCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Procurar atualizações…") { UpdateChecker.shared.checkNow() }
            Button("Termos e privacidade") { openWindow(id: "terms") }
        }
        CommandGroup(replacing: .newItem) {
            Button("Adicionar pasta…") { model.addFolder() }
                .keyboardShortcut("o")
            Button("Adicionar Jellyfin…") { model.addJellyfin() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Ejetar CD") { model.ejectDisc() }
                .keyboardShortcut("e")
                .disabled(model.ejectableDisc == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Player com fila") { model.windowMode = .player }
                .keyboardShortcut("1")
            Button("Player com pastas") { model.windowMode = .browser }
                .keyboardShortcut("2")
            Button("Compacto") { model.windowMode = .compact }
                .keyboardShortcut("3")
            Button(Ambient.shared.isOpen ? String(localized: "Sair do Ambiente") : String(localized: "Ambiente")) {
                Ambient.shared.toggle(model)
            }
            .keyboardShortcut("4")
            Menu("Opções do Ambiente") { AmbientMenuItems(model: model) }
            Button(model.windowMode == .browser ? String(localized: "Mostrar fila") : String(localized: "Mostrar pastas")) { model.toggleBrowser() }
                .keyboardShortcut("b")
            Toggle("Mostrar capas", isOn: Binding(get: { model.showsArtwork }, set: { model.showsArtwork = $0 }))
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Capa errada ou em falta…") { model.fixingArtwork = model.player.current?.entry }
                .disabled(!model.canFixArtwork)
            Toggle("Mostrar espectro", isOn: Binding(get: { model.showsSpectrum }, set: { model.showsSpectrum = $0 }))
                .keyboardShortcut("v", modifiers: [.command, .option])
            Divider()
            Menu("Skin") { SkinMenuItems() }
            Menu("Fonte") { FontMenuItems() }
        }
        CommandMenu("Controlos") {
            // While a sheet with text fields is open, Space and ⌘← ⌘→ ⌘↑ ⌘↓ belong to the field:
            // a menu key equivalent would otherwise take them before the field sees them.
            let typing = model.showingJellyfinLogin || model.fixingArtwork != nil
            Button(model.player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar")) { model.playOrBrowse() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(typing)
            Button("Parar") { model.player.stop() }
                .keyboardShortcut(".")
            Button("Seguinte") { model.player.next() }
                .keyboardShortcut(.rightArrow)
                .disabled(typing)
            Button("Anterior") { model.player.previous() }
                .keyboardShortcut(.leftArrow)
                .disabled(typing)
            Button("Avançar 10 s") { model.player.skip(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(typing || model.player.current == nil)
            Button("Recuar 10 s") { model.player.skip(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(typing || model.player.current == nil)
            Divider()
            Button("Aumentar volume") { model.player.changeVolume(by: 0.05) }
                .keyboardShortcut(.upArrow)
                .disabled(typing)
            Button("Baixar volume") { model.player.changeVolume(by: -0.05) }
                .keyboardShortcut(.downArrow)
                .disabled(typing)
            Button("Equalizador…") { model.showsEqualizer = true }
                .keyboardShortcut("e", modifiers: [.command, .option])
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
            Button("Limpar fila") { model.player.clear() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(model.player.queue.isEmpty)
        }
    }
}
