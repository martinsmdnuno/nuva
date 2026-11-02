import AppKit
import IOKit.pwr_mgt
import Observation
import SwiftUI

/// What the ambient screen shows. ← → cycle through them.
enum AmbientFace: String, CaseIterable, Sendable {
    /// The window's display at the scale of the room.
    case display
    /// The time of day, with the playing track on one line.
    case clock

    var name: String {
        switch self {
        case .display: String(localized: "Ecrã")
        case .clock: String(localized: "Relógio")
        }
    }

    func moved(by step: Int) -> AmbientFace {
        let all = Self.allCases
        let index = (all.firstIndex(of: self)! + step + all.count) % all.count
        return all[index]
    }
}

/// Ambient mode (View ▸ Ambient, ⌘4): a full-screen window, in its own Space, that is all display.
/// Nothing to operate; the main window stays as it was.
@MainActor
@Observable
final class Ambient {
    static let shared = Ambient()

    var face: AmbientFace {
        didSet { defaults.set(face.rawValue, forKey: "ambientFace") }
    }

    /// View ▸ Ambient ▸ Dim: the content at 40% for the night.
    var dims: Bool {
        didSet { defaults.set(dims, forKey: "ambientDims") }
    }

    private(set) var isOpen = false

    /// Names of the connected screens, for View ▸ Ambient ▸ On….
    private(set) var screenNames: [String] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var window: AmbientWindow?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var assertion: IOPMAssertionID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        face = AmbientFace(rawValue: defaults.string(forKey: "ambientFace") ?? "") ?? .display
        dims = defaults.bool(forKey: "ambientDims")
        updateScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreens() }
        }
    }

    func toggle(_ model: AppModel) {
        if isOpen { close() } else { open(model) }
    }

    /// Opens on `screenIndex`, or on the screen of the window in front.
    func open(_ model: AppModel, screenIndex: Int? = nil) {
        if let window {
            // Already open: move it by closing and opening again on the other screen.
            guard let screenIndex, NSScreen.screens.indices.contains(screenIndex),
                  window.screen != NSScreen.screens[screenIndex] else { return }
            finish()
        }
        let screens = NSScreen.screens
        let target = screenIndex.flatMap { screens.indices.contains($0) ? screens[$0] : nil }
            ?? NSApp.keyWindow?.screen ?? NSScreen.main ?? screens.first
        guard let target else { return }

        let window = AmbientWindow(
            contentRect: target.frame, styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .skin(.display)
        window.title = String(localized: "Ambiente")
        window.contentView = NSHostingView(rootView: AmbientView().environment(model))
        window.setFrame(target.frame, display: false)
        window.onExitFullScreen = { [weak self] in self?.finish() }
        self.window = window
        isOpen = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let key = (code: event.keyCode, flags: event.modifierFlags, window: event.windowNumber)
            let handled = MainActor.assumeIsolated {
                guard let self, key.window == self.window?.windowNumber else { return false }
                return self.handle(key.code, key.flags, player: model.player)
            }
            return handled ? nil : event
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    /// Leaves full screen; the window closes once the animation ends.
    func close() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            finish()
        }
    }

    /// Keeps the display awake while the music plays (and only while ambient is open).
    func keepAwake(_ on: Bool) {
        if on, assertion == nil {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NuVa ambient mode" as CFString, &id)
            if result == kIOReturnSuccess { assertion = id }
        } else if !on, let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
        }
    }

    private func finish() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        keepAwake(false)
        window?.onExitFullScreen = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        isOpen = false
    }

    /// Esc and ⌘4 leave, ← → change the face, Space plays or pauses.
    /// Runs before the menus, so it also works with the main window closed (no menu bar).
    private func handle(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, player: PlayerController) -> Bool {
        let modifiers = flags.intersection(.deviceIndependentFlagsMask)
        switch (keyCode, modifiers) {
        case (53, []), (21, .command):  // Esc, ⌘4
            close()
        case (123, let m) where m.subtracting([.numericPad, .function]).isEmpty:  // ←
            face = face.moved(by: -1)
        case (124, let m) where m.subtracting([.numericPad, .function]).isEmpty:  // →
            face = face.moved(by: 1)
        case (49, []):  // Space
            player.togglePlayPause()
        default:
            return false
        }
        return true
    }

    private func updateScreens() {
        screenNames = NSScreen.screens.map(\.localizedName)
    }
}

/// Reports when it leaves full screen, however that happened (Esc, ⌘4 or the system).
final class AmbientWindow: NSWindow, NSWindowDelegate {
    var onExitFullScreen: (() -> Void)?

    override init(
        contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    func windowDidExitFullScreen(_ notification: Notification) {
        onExitFullScreen?()
    }
}
