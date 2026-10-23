import AppKit
import SwiftUI

// Motion tokens from docs/design-system/README.md ("Motion"). Movement only shows what a
// hardware control would do: a key travels, an LED glows and fades, content changes in place.
// Nothing moves on its own, and everything snaps with Reduce Motion.

enum Motion {
    /// Key going down: fast, like a real key bottoming out.
    static let press = Animation.easeOut(duration: 0.06)
    /// Key coming back up: the spring returns it.
    static let release = Animation.spring(duration: 0.18, bounce: 0.3)
    /// LED lighting: almost immediate.
    static let ledOn = Animation.easeOut(duration: 0.08)
    /// LED going out: a short afterglow, like a filament.
    static let ledOff = Animation.easeOut(duration: 0.35)
    /// Hover backgrounds and resting colours.
    static let hover = Animation.easeOut(duration: 0.12)
    /// A state change in place: a new track, a switch thrown, a row added or removed.
    static let state = Animation.easeInOut(duration: 0.2)
    /// Equalizer faders going to a preset, like motorised ones.
    static let fader = Animation.easeInOut(duration: 0.3)
}

extension View {
    /// `animation(_:value:)` that turns off with Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// `withAnimation` that turns off with Reduce Motion, for changes made outside a view.
@MainActor
func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return try withAnimation(reduce ? nil : animation, body)
}
