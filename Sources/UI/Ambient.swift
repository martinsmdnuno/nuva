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
    /// The equalizer's 10 bands as tall columns of segments.
    case spectrum
    /// Left and right levels, as two ladders of segments.
    case meters

    var name: String {
        switch self {
        case .display: String(localized: "Ecrã")
        case .clock: String(localized: "Relógio")
        case .spectrum: String(localized: "Espectro")
        case .meters: String(localized: "Medidores")
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
        didSet {
            defaults.set(face.rawValue, forKey: "ambientFace")
            faceShownAt = .now
        }
    }

    /// View ▸ Ambient Options ▸ OLED Protection, on by default: a wide slow drift, dimmer static
    /// parts, a blinking colon, a new face every 20 minutes, and rest after an hour untouched.
    var protectsOLED: Bool {
        didSet { defaults.set(protectsOLED, forKey: "ambientProtectsOLED") }
    }

    /// The last key or mouse movement: an hour after it, with OLED protection, the screen rests.
    private(set) var lastInteraction = Date.now

    static let restAfter: TimeInterval = 3600
    static let changeFaceAfter: TimeInterval = 1200

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
    @ObservationIgnored private var faceShownAt = Date.now
    @ObservationIgnored private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        face = AmbientFace(rawValue: defaults.string(forKey: "ambientFace") ?? "") ?? .display
        dims = defaults.bool(forKey: "ambientDims")
        protectsOLED = defaults.object(forKey: "ambientProtectsOLED") as? Bool ?? true
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

        lastInteraction = .now
        faceShownAt = .now
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
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

    /// Resting: OLED protection on and an hour without a key or the mouse.
    func isResting(at date: Date) -> Bool {
        protectsOLED && date.timeIntervalSince(lastInteraction) > Self.restAfter
    }

    /// A key or the mouse. Mouse moves arrive many times a second; one a second is enough.
    func noteInteraction() {
        if Date.now.timeIntervalSince(lastInteraction) > 1 { lastInteraction = .now }
    }

    /// With OLED protection, a new face every 20 minutes while nobody is looking at the controls.
    func tick(at date: Date = .now) {
        guard protectsOLED, !isResting(at: date), date.timeIntervalSince(faceShownAt) > Self.changeFaceAfter else { return }
        face = face.moved(by: 1)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
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
        let wasResting = isResting(at: .now)
        lastInteraction = .now
        // Resting, the first key only wakes the screen (Esc and ⌘4 still leave).
        if wasResting, !(keyCode == 53 && modifiers.isEmpty), !(keyCode == 21 && modifiers == .command) { return true }
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
