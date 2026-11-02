import Foundation
import Testing
@testable import NuVa

@MainActor
struct AmbientTests {
    @Test func facesCycleBothWays() {
        #expect(AmbientFace.display.moved(by: 1) == .clock)
        #expect(AmbientFace.clock.moved(by: 1) == .spectrum)
        #expect(AmbientFace.meters.moved(by: 1) == .needles)
        #expect(AmbientFace.valves.moved(by: 1) == .display)
        #expect(AmbientFace.display.moved(by: -1) == .valves)
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

    @Test func facesChosenByHandAreCounted() {
        let defaults = UserDefaults(suiteName: "ambient-tests-hand")!
        defaults.removePersistentDomain(forName: "ambient-tests-hand")
        let ambient = Ambient(defaults: defaults)
        ambient.face = .display
        ambient.changeFace(by: 1)
        #expect(ambient.face == .clock && ambient.changesByHand == 1)
        // The 20-minute change isn't by hand: no name pops up for it.
        ambient.tick(at: .now.addingTimeInterval(Ambient.changeFaceAfter + 1))
        #expect(ambient.changesByHand == 1)
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

    @Test func vuScaleFollowsVoltage() {
        #expect(AmbientNeedlesFaceTestHook.position(-20) == 0)
        #expect(abs(AmbientNeedlesFaceTestHook.position(3) - 1) < 0.0001)
        // 0 VU sits at about 70% of the arc, as on a real meter, not at 87% (23 dB linear).
        let zero = AmbientNeedlesFaceTestHook.position(0)
        #expect(zero > 0.65 && zero < 0.75)
    }

    @Test func slowMeterRisesGradually() {
        let meter = SlowMeter(floor: -40, ceiling: 0, rise: 9, fall: 5)
        let start = Date()
        meter.update(at: start, measured: [(0, 0), (0, 0)])
        meter.update(at: start.addingTimeInterval(1 / 30), measured: [(0, 0), (0, 0)])
        #expect(meter.levels[0] > 0.2 && meter.levels[0] < 0.4)
        for i in 2...60 { meter.update(at: start.addingTimeInterval(Double(i) / 30), measured: [(0, 0), (0, 0)]) }
        #expect(meter.levels[0] > 0.99)
        #expect(meter.peaks[0] == 0)
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
