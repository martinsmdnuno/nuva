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

/// View ▸ Font: follow the skin, or a fixed font set.
struct FontMenuItems: View {
    var body: some View {
        let store = SkinStore.shared
        Toggle(String(localized: "Predefinição da skin (\(store.current.fontSet.name))"), isOn: Binding(
            get: { store.fontChoice == nil },
            set: { if $0 { store.fontChoice = nil } }
        ))
        Divider()
        ForEach(FontSet.allCases, id: \.self) { set in
            Toggle(set.name, isOn: Binding(
                get: { store.fontChoice == set },
                set: { if $0 { store.fontChoice = set } }
            ))
        }
    }
}

/// View ▸ Ambient options: the face, dimming, and which screen.
struct AmbientMenuItems: View {
    let model: AppModel

    var body: some View {
        let ambient = Ambient.shared
        ForEach(AmbientFace.allCases, id: \.self) { face in
            Toggle(face.name, isOn: Binding(
                get: { ambient.face == face },
                set: { if $0 { ambient.face = face } }
            ))
        }
        Divider()
        Toggle("Escurecer", isOn: Binding(get: { ambient.dims }, set: { ambient.dims = $0 }))
        Toggle("Proteção OLED", isOn: Binding(get: { ambient.protectsOLED }, set: { ambient.protectsOLED = $0 }))
        if ambient.screenNames.count > 1 {
            Divider()
            ForEach(Array(ambient.screenNames.enumerated()), id: \.offset) { index, name in
                Button(String(localized: "Abrir em \(name)")) { ambient.open(model, screenIndex: index) }
            }
        }
    }
}
