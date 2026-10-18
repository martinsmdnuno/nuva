import SwiftUI

// Tokens from docs/design-system/tokens.json. Colours live in Assets.xcassets
// under the same name as the token (Any = Aluminium, Dark = Lead).

extension Color {
    static let surface0 = Color("surface-0")
    static let surface1 = Color("surface-1")
    static let surface2 = Color("surface-2")
    static let display = Color("display")
    static let displayInk = Color("display-ink")
    static let displayMuted = Color("display-muted")
    static let displayTrack = Color("display-track")
    static let ink = Color("ink")
    static let inkMuted = Color("ink-muted")
    static let line = Color("line")
    static let keyFace = Color("key-face")
    static let keyMode = Color("key-mode")
    static let keyPlay = Color("key-play")
    static let keyInk = Color("key-ink")
    static let keyModeInk = Color("key-mode-ink")
    static let track = Color("track")
    static let fill = Color("fill")
    static let led = Color("led")
    static let ledOff = Color("led-off")
    static let signal = Color("signal")
    static let danger = Color("danger")
    static let focus = Color("focus")
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
