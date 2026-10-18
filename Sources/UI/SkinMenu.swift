import SwiftUI

/// One checked item per skin, ⌥⌘1, ⌥⌘2… in order. Used in View ▸ Skin and in the mini player.
struct SkinMenuItems: View {
    var body: some View {
        let store = SkinStore.shared
        ForEach(Array(Skin.all.enumerated()), id: \.element.id) { index, skin in
            Toggle(skin.name, isOn: Binding(
                get: { store.current == skin },
                set: { if $0 { store.current = skin } }
            ))
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
        }
    }
}
