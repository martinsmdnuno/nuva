import Foundation
import Testing
@testable import NuVa

@MainActor
struct AmbientTests {
    @Test func facesCycleBothWays() {
        #expect(AmbientFace.display.moved(by: 1) == .clock)
        #expect(AmbientFace.clock.moved(by: 1) == .display)
        #expect(AmbientFace.display.moved(by: -1) == .clock)
    }

    @Test func startsOnTheDisplayFace() {
        let defaults = UserDefaults(suiteName: "ambient-tests-default")!
        defaults.removePersistentDomain(forName: "ambient-tests-default")
        let ambient = Ambient(defaults: defaults)
        #expect(ambient.face == .display)
        #expect(!ambient.dims)
        #expect(!ambient.isOpen)
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
