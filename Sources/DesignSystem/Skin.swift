import AppKit
import Observation
import os

/// The design system's colour tokens (docs/design-system/tokens.json). A skin gives each
/// one a value; it never adds a role or moves the accent to another one.
enum ColorToken: String, CaseIterable, Sendable {
    case surface0 = "surface-0"
    case surface1 = "surface-1"
    case surface2 = "surface-2"
    case display
    case displayInk = "display-ink"
    case displayMuted = "display-muted"
    case displayTrack = "display-track"
    case ink
    case inkMuted = "ink-muted"
    case line
    case keyFace = "key-face"
    case keyMode = "key-mode"
    case keyPlay = "key-play"
    case keyInk = "key-ink"
    case keyModeInk = "key-mode-ink"
    case track
    case fill
    case led
    case ledOff = "led-off"
    case signal
    case danger
    case focus
}

/// A skin: colours and appearance policy. Same views, layout and sizes in every skin.
struct Skin: Identifiable, Sendable, Equatable {
    enum Appearance: Sendable {
        /// Light and dark variants, following the system (Nuno: Aluminium and Lead).
        case followsSystem
        /// Always dark, whatever the system appearance.
        case alwaysDark
    }

    /// Light and dark sRGB values of a token, as 0xRRGGBB.
    struct Pair: Sendable, Equatable {
        let light: UInt32
        let dark: UInt32
    }

    let id: String
    let name: String
    let appearance: Appearance
    /// `nil`: the colour sets in Assets.xcassets, named like the tokens.
    let palette: [ColorToken: Pair]?

    static let nuno = Skin(id: "nuno", name: "Nuno", appearance: .followsSystem, palette: nil)

    static let all: [Skin] = [.nuno]

    static func with(id: String?) -> Skin {
        all.first { $0.id == id } ?? .nuno
    }

    /// The token's colour, resolved for `drawing` (light or dark).
    func color(_ token: ColorToken, for drawing: NSAppearance) -> NSColor {
        guard let pair = palette?[token] else {
            // The asset colour is itself dynamic: resolve it for this appearance.
            let named = NSColor(named: token.rawValue) ?? .magenta
            var resolved = named
            drawing.performAsCurrentDrawingAppearance {
                resolved = named.usingColorSpace(.sRGB) ?? named
            }
            return resolved
        }
        let dark = drawing.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let hex = dark || appearance == .alwaysDark ? pair.dark : pair.light
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}

/// The current skin, persisted in UserDefaults (`skin`).
@MainActor
@Observable
final class SkinStore {
    static let shared = SkinStore()

    var current: Skin {
        didSet {
            guard current != oldValue else { return }
            defaults.set(current.id, forKey: "skin")
            let skin = current
            Self.active.withLock { $0 = skin }
            applyAppearance()
        }
    }

    /// Read by the dynamic colours, which AppKit may resolve off the main thread.
    nonisolated static let active = OSAllocatedUnfairLock(initialState: Skin.nuno)

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let skin = Skin.with(id: defaults.string(forKey: "skin"))
        current = skin
        Self.active.withLock { $0 = skin }
    }

    /// Always-dark skins force the dark appearance; the others follow the system.
    func applyAppearance() {
        NSApp?.appearance = current.appearance == .alwaysDark ? NSAppearance(named: .darkAqua) : nil
    }
}

extension NSColor {
    /// A token's colour in the current skin, resolved for the appearance it is drawn in.
    static func skin(_ token: ColorToken) -> NSColor {
        NSColor(name: NSColor.Name(token.rawValue)) { appearance in
            SkinStore.active.withLock { $0 }.color(token, for: appearance)
        }
    }
}
