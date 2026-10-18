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

/// A skin: colours, appearance policy and default font set. Same views, layout and sizes in every skin.
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
    /// Used unless the user picks another set in View ▸ Font.
    let fontSet: FontSet
    /// `nil`: the colour sets in Assets.xcassets, named like the tokens.
    let palette: [ColorToken: Pair]?

    static let nuno = Skin(id: "nuno", name: "Nuno", appearance: .followsSystem, fontSet: .inter, palette: nil)

    /// Graphite, from NuVa_Design_Spec_v1 (docs/design-system/skins/graphite.md): the spec's colours,
    /// adjusted so every text pair passes 4.5:1 and the layers can be told apart. Only the accent differs.
    static let graphiteOrange = graphite(id: "graphite-orange", name: "Graphite Orange", accent: 0xFF6A00, selected: 0x382E22)
    static let graphiteGreen = graphite(id: "graphite-green", name: "Graphite Green", accent: 0x20D66B, selected: 0x1D3628)

    static let all: [Skin] = [.nuno, .graphiteOrange, .graphiteGreen]

    private static func graphite(id: String, name: String, accent: UInt32, selected: UInt32) -> Skin {
        let dark: [ColorToken: UInt32] = [
            .surface0: 0x0B0F10,
            .surface1: 0x1C2427,
            .surface2: selected,
            .display: 0x050708,
            .displayInk: 0xF2F4F5,
            .displayMuted: 0x9AA3A7,
            .displayTrack: 0x252C2F,
            .ink: 0xF2F4F5,
            .inkMuted: 0x9AA3A7,
            .line: 0x2A3032,
            .keyFace: 0xC9CED0,
            .keyMode: 0x5B656C,
            // One accent, in its three roles: the play key, the LEDs and the playing track.
            .keyPlay: accent,
            .keyInk: 0x0B0F10,
            .keyModeInk: 0xF2F4F5,
            .track: 0x363E41,
            .fill: 0xC9CED0,
            .led: accent,
            .ledOff: 0x2A3032,
            .signal: accent,
            .danger: 0xFF6F8A,
            .focus: 0x8FB4E3,
        ]
        return Skin(
            id: id, name: name, appearance: .alwaysDark, fontSet: .system,
            palette: dark.mapValues { Pair(light: $0, dark: $0) })
    }

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

/// The current skin and font set, persisted in UserDefaults (`skin`, `fontSet`).
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
            publishFontSet()
            applyAppearance()
        }
    }

    /// The font set the user picked; `nil` follows the skin.
    var fontChoice: FontSet? {
        didSet {
            guard fontChoice != oldValue else { return }
            defaults.set(fontChoice?.rawValue ?? "skin", forKey: "fontSet")
            publishFontSet()
        }
    }

    var fontSet: FontSet { fontChoice ?? current.fontSet }

    /// Changes when anything drawn changes: the window rebuilds on it.
    var renderID: String { "\(current.id)-\(fontSet.rawValue)" }

    /// Read by the dynamic colours, which AppKit may resolve off the main thread.
    nonisolated static let active = OSAllocatedUnfairLock(initialState: Skin.nuno)
    /// Read by Typography, from any view.
    nonisolated static let activeFonts = OSAllocatedUnfairLock(initialState: FontSet.inter)

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let skin = Skin.with(id: defaults.string(forKey: "skin"))
        current = skin
        fontChoice = FontSet(rawValue: defaults.string(forKey: "fontSet") ?? "")
        Self.active.withLock { $0 = skin }
        publishFontSet()
    }

    private func publishFontSet() {
        let set = fontSet
        Self.activeFonts.withLock { $0 = set }
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
