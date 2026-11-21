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
        let model = AppModel(systemIntegration: true)
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window("NuVa", id: "main") {
            ContentView()
                .environment(model)
                // Once, after the window is up: may NuVa report use and failures?
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    model.askAboutReports()
                }
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
    /// The app's model, for what reaches the delegate and not a view: the Finder and the Dock.
    @MainActor static weak var model: AppModel?

    /// "Open With", a double-click on a file NuVa is the default for, or a drop on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model = Self.model else { return }
        Task { await model.open(urls) }
    }

    /// Right-click on the Dock icon: what is playing, and the three keys.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let player = Self.model?.player, !player.queue.isEmpty else { return nil }
        let menu = NSMenu()
        if let entry = player.current?.entry {
            menu.addItem(withTitle: entry.title, action: nil, keyEquivalent: "")
            if !entry.folderLine.isEmpty { menu.addItem(withTitle: entry.folderLine, action: nil, keyEquivalent: "") }
            menu.addItem(.separator())
        }
        let keys: [(String, Selector)] = [
            (player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar"), #selector(dockPlayPause)),
            (String(localized: "Seguinte"), #selector(dockNext)),
            (String(localized: "Anterior"), #selector(dockPrevious)),
        ]
        for (title, action) in keys {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        return menu
    }

    @MainActor @objc private func dockPlayPause() { Self.model?.player.togglePlayPause() }
    @MainActor @objc private func dockNext() { Self.model?.player.next() }
    @MainActor @objc private func dockPrevious() { Self.model?.player.previous() }

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
        CommandGroup(replacing: .appInfo) {
            Button("Acerca da NuVa") { AboutPanel.show() }
        }
        CommandGroup(after: .appInfo) {
            Button("Procurar atualizações…") { UpdateChecker.shared.checkNow() }
            Button("Termos e privacidade") { openWindow(id: "terms") }
            Button("Mostrar registo de erros") { Log.shared.reveal() }
            Toggle("Enviar uso e falhas anónimos", isOn: Binding(get: { model.sendsReports }, set: { model.sendsReports = $0 }))
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
            Toggle("Pastas recentes primeiro", isOn: Binding(
                get: { model.browser.folderOrder == .recent },
                set: { model.browser.folderOrder = $0 ? .recent : .name }))
                .keyboardShortcut("n", modifiers: [.command, .option])
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
            Toggle("Ajustar a saída à faixa", isOn: Binding(get: { model.matchesOutputRate }, set: { model.matchesOutputRate = $0 }))
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
            Button("Mostrar faixa no Finder") { model.reveal(model.player.current?.entry) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canReveal(model.player.current?.entry))
            Button("Limpar fila") { model.player.clear() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(model.player.queue.isEmpty)
        }
    }
}
