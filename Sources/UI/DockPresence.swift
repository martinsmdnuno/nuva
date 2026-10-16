import AppKit

/// Põe ou tira a NuVa do Dock (com a janela fechada fica só na barra de menus).
@MainActor
enum DockPresence {
    static func show(_ visible: Bool) {
        guard let app = NSApp else { return }
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        // Ao voltar ao Dock com a app já aberta, o macOS mostra o ícone genérico
        // se a app não repuser o seu.
        if visible { app.applicationIconImage = NSImage(named: NSImage.applicationIconName) }
    }
}
