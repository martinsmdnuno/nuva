import AppKit

/// Adds NuVa to or removes it from the Dock (with the window closed it stays only in the menu bar).
@MainActor
enum DockPresence {
    static func show(_ visible: Bool) {
        guard let app = NSApp else { return }
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        // When returning to the Dock with the app already open, macOS shows the generic icon
        // unless the app restores its own.
        if visible { app.applicationIconImage = NSImage(named: NSImage.applicationIconName) }
    }
}
