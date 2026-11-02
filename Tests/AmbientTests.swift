import Foundation
import Testing
@testable import NuVa

@MainActor
struct AmbientTests {
    @Test func facesCycleBothWays() {
        #expect(AmbientFace.display.moved(by: 1) == .clock)
        #expect(AmbientFace.clock.moved(by: 1) == .spectrum)
        #expect(AmbientFace.meters.moved(by: 1) == .display)
        #expect(AmbientFace.display.moved(by: -1) == .meters)
    }

    @Test func startsOnTheDisplayFace() {
        let defaults = UserDefaults(suiteName: "ambient-tests-default")!
        defaults.removePersistentDomain(forName: "ambient-tests-default")
        let ambient = Ambient(defaults: defaults)
        #expect(ambient.face == .display)
        #expect(!ambient.dims)
        #expect(!ambient.isOpen)
        #expect(ambient.protectsOLED)
    }

    @Test func oledProtectionChangesFaceAndRests() {
        let defaults = UserDefaults(suiteName: "ambient-tests-oled")!
        defaults.removePersistentDomain(forName: "ambient-tests-oled")
        let ambient = Ambient(defaults: defaults)
        ambient.face = .display
        ambient.tick(at: .now.addingTimeInterval(60))
        #expect(ambient.face == .display)
        ambient.tick(at: .now.addingTimeInterval(Ambient.changeFaceAfter + 1))
        #expect(ambient.face == .clock)
        #expect(!ambient.isResting(at: .now))
        #expect(ambient.isResting(at: .now.addingTimeInterval(Ambient.restAfter + 1)))
        ambient.protectsOLED = false
        #expect(!ambient.isResting(at: .now.addingTimeInterval(Ambient.restAfter + 1)))
        ambient.tick(at: .now.addingTimeInterval(Ambient.changeFaceAfter * 3))
        #expect(ambient.face == .clock)
    }

    @Test func oledDriftStaysWithinEightPercent() {
        let size = CGSize(width: 3840, height: 2160)
        var widest = CGSize.zero
        for minute in stride(from: 0, to: 60 * 24 * 3, by: 7) {
            let shift = AmbientView.drift(at: Date(timeIntervalSinceReferenceDate: Double(minute) * 60), in: size, protects: true)
            widest = CGSize(width: max(widest.width, abs(shift.width)), height: max(widest.height, abs(shift.height)))
        }
        #expect(widest.width <= size.width * 0.08 && widest.height <= size.height * 0.08)
        // It actually travels: most of the range is used over three days.
        #expect(widest.width > size.width * 0.06 && widest.height > size.height * 0.06)
    }

    @Test func remembersFaceAndDimming() {
        let defaults = UserDefaults(suiteName: "ambient-tests")!
        defaults.removePersistentDomain(forName: "ambient-tests")
        let ambient = Ambient(defaults: defaults)
        ambient.face = .clock
        ambient.dims = true
        let reopened = Ambient(defaults: defaults)
        #expect(reopened.face == .clock)
        #expect(reopened.dims)
    }
}
