import SwiftUI

// Tokens from docs/design-system/tokens.json. Colours come from the current skin
// (Skin.swift); the Nuno skin reads Assets.xcassets (Any = Aluminium, Dark = Lead).

extension Color {
    init(_ token: ColorToken) {
        self.init(nsColor: .skin(token))
    }

    static let surface0 = Color(ColorToken.surface0)
    static let surface1 = Color(ColorToken.surface1)
    static let surface2 = Color(ColorToken.surface2)
    static let display = Color(ColorToken.display)
    static let displayInk = Color(ColorToken.displayInk)
    static let displayMuted = Color(ColorToken.displayMuted)
    static let displayTrack = Color(ColorToken.displayTrack)
    static let ink = Color(ColorToken.ink)
    static let inkMuted = Color(ColorToken.inkMuted)
    static let line = Color(ColorToken.line)
    static let keyFace = Color(ColorToken.keyFace)
    static let keyMode = Color(ColorToken.keyMode)
    static let keyPlay = Color(ColorToken.keyPlay)
    static let keyInk = Color(ColorToken.keyInk)
    static let keyModeInk = Color(ColorToken.keyModeInk)
    static let track = Color(ColorToken.track)
    static let fill = Color(ColorToken.fill)
    static let led = Color(ColorToken.led)
    static let ledOff = Color(ColorToken.ledOff)
    static let signal = Color(ColorToken.signal)
    static let danger = Color(ColorToken.danger)
    static let focus = Color(ColorToken.focus)
}

enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
}

enum Radius {
    static let sm: CGFloat = 3
    static let md: CGFloat = 6
    static let lg: CGFloat = 10
}

enum Size {
    /// Height of all icon keys.
    static let key: CGFloat = 36
    static let keyWSm: CGFloat = 32
    static let keyWMd: CGFloat = 40
    static let keyWLg: CGFloat = 56
    static let keyText: CGFloat = 28
    static let led: CGFloat = 4
    static let row: CGFloat = 28
    static let bar: CGFloat = 2
}
