import SwiftUI

// Tokens de docs/design-system/tokens.json. As cores vivem em Assets.xcassets
// com o mesmo nome do token (Any = Alumínio, Dark = Chumbo).

extension Color {
    static let surface0 = Color("surface-0")
    static let surface1 = Color("surface-1")
    static let surface2 = Color("surface-2")
    static let display = Color("display")
    static let displayInk = Color("display-ink")
    static let displayMuted = Color("display-muted")
    static let ink = Color("ink")
    static let inkMuted = Color("ink-muted")
    static let line = Color("line")
    static let keyFace = Color("key-face")
    static let keyFacePressed = Color("key-face-pressed")
    static let keyEdge = Color("key-edge")
    static let track = Color("track")
    static let fill = Color("fill")
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
    static let keySm: CGFloat = 28
    static let keyMd: CGFloat = 36
    static let keyLg: CGFloat = 44
    static let row: CGFloat = 28
    static let bar: CGFloat = 4
}
