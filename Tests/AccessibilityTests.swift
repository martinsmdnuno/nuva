import Testing
@testable import NuVa

struct AccessibilityTests {
    @Test func keyNamesDropTheirShortcuts() {
        #expect(ControlBar.spoken("Anterior ⌘←") == "Anterior")
        #expect(ControlBar.spoken("Aleatório ligado ⌥⌘S") == "Aleatório ligado")
        #expect(ControlBar.spoken("Repetir uma") == "Repetir uma")
    }
}
