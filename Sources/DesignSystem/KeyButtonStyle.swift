import SwiftUI

/// The device's flat key, like on a Braun calculator. The app's only button style.
/// No outline: the face tone tells the function. With an icon (all 36px tall) or a label.
struct KeyButtonStyle: ButtonStyle {
    enum Tone {
        /// Play/pause: amber, 56px. One per window.
        case play
        /// Previous and next: light grey, 40px.
        case transport
        /// Mode, output and text buttons: mid grey, 32px.
        case mode

        var face: Color {
            switch self {
            case .play: .keyPlay
            case .transport: .keyFace
            case .mode: .keyMode
            }
        }

        var ink: Color { self == .mode ? .keyModeInk : .keyInk }

        var width: CGFloat {
            switch self {
            case .play: Size.keyWLg
            case .transport: Size.keyWMd
            case .mode: Size.keyWSm
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .play: 18
            case .transport: 16
            case .mode: 14
            }
        }
    }

    var tone: Tone = .transport
    /// Text button: key-text height, width from the label, always in the mode tone.
    var isText = false

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, tone: isText ? .mode : tone, isText: isText)
    }

    private struct KeyBody: View {
        let configuration: Configuration
        let tone: Tone
        let isText: Bool
        /// The button's own focus (the `isFocused` environment also lights up when
        /// the surrounding list has focus, which lit every key inside it).
        @FocusState private var isFocused: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)

            configuration.label
                .font(isText ? .dsLabel : .system(size: tone.iconSize, weight: .regular))
                .foregroundStyle(tone.ink)
                .padding(.horizontal, isText ? Space.s3 : 0)
                .frame(width: isText ? nil : tone.width, height: isText ? Size.keyText : Size.key)
                .background {
                    shape.fill(tone.face)
                    // Pressed: the face darkens while the mouse is down.
                    if configuration.isPressed { shape.fill(Color.black.opacity(0.15)) }
                }
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: Radius.sm + 4, style: .continuous)
                            .strokeBorder(Color.focus, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .contentShape(shape)
                // Only joins the focus loop with full keyboard access, like native buttons.
                .focusable(interactions: .activate)
                .focused($isFocused)
        }
    }
}

extension ButtonStyle where Self == KeyButtonStyle {
    static func key(_ tone: KeyButtonStyle.Tone) -> KeyButtonStyle { KeyButtonStyle(tone: tone) }

    static var keyText: KeyButtonStyle { KeyButtonStyle(isText: true) }
}

/// Indicator light: on state, playback, track playing.
struct LED: View {
    var isOn: Bool
    var size: CGFloat = Size.led

    var body: some View {
        Circle()
            .fill(isOn ? Color.led : Color.ledOff)
            .frame(width: size, height: size)
    }
}

extension View {
    /// Turns off the native ring; KeyButtonStyle draws its own in `focus`.
    func keyFocus() -> some View { focusEffectDisabled() }

    /// LED above the key. `nil` leaves the space empty, so the faces line up
    /// with those of keys that have a state.
    func keyLED(_ isOn: Bool?) -> some View {
        VStack(spacing: Space.s1) {
            if let isOn {
                LED(isOn: isOn)
            } else {
                Color.clear.frame(width: Size.led, height: Size.led)
            }
            self
        }
    }

    /// Legend printed on the chassis below a group of keys or in front of an area.
    func legend() -> some View {
        font(.dsLegend).foregroundStyle(Color.inkMuted)
    }
}
