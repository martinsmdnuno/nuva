import AppKit
import Observation
import os

/// A skin: colours, appearance policy and default font set. Same views, layout and sizes in every skin.
struct Skin: Identifiable, Sendable, Equatable {
    enum Appearance: Sendable {
        /// Light and dark variants, following the system (Rams: Aluminium and Lead).
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

    static let rams = Skin(id: "rams", name: "Rams", appearance: .followsSystem, fontSet: .inter, palette: nil)

    /// Graphite, from NuVa_Design_Spec_v1 (docs/design-system/skins/graphite.md): the spec's colours,
    /// adjusted so every text pair passes 4.5:1 and the layers can be told apart. Only the accent differs.
    static let graphiteOrange = Skin(
        id: "graphite-orange", name: "Graphite Orange", appearance: .alwaysDark, fontSet: .system,
        palette: TokenPalette.graphiteOrange.mapValues { Pair(light: $0, dark: $0) })

    /// Phosphor (docs/design-system/skins/phosphor.md): after the classic shareware players. A black display
    /// with phosphor-green ink, a blue-grey chassis, silver keys and a blue selected row.
    static let phosphor = Skin(
        id: "phosphor", name: "Phosphor", appearance: .alwaysDark, fontSet: .inter,
        palette: TokenPalette.phosphor.mapValues { Pair(light: $0, dark: $0) })

    static let all: [Skin] = [.rams, .graphiteOrange, .phosphor]

    static func with(id: String?) -> Skin {
        // "nuno" is Rams's id before 1.5; Graphite Green was retired in 1.10.1 for its orange twin.
        let id = id == "nuno" ? Skin.rams.id : id == "graphite-green" ? Skin.graphiteOrange.id : id
        return all.first { $0.id == id } ?? .rams
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
    nonisolated static let active = OSAllocatedUnfairLock(initialState: Skin.rams)
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
