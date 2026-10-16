import Foundation
import Testing
@testable import NuVa

@MainActor
struct EqualizerTests {
    @Test func flatBandPassesThrough() {
        #expect(EQTap.peaking(frequency: 1000, gain: 0, sampleRate: 48_000) == [1, 0, 0, 0, 0])
        // Acima de Nyquist (16 kHz a 22,05 kHz de amostragem) fica plano.
        #expect(EQTap.peaking(frequency: 16_000, gain: 6, sampleRate: 22_050) == [1, 0, 0, 0, 0])
    }

    @Test func boostRaisesGainAtCentre() {
        let c = EQTap.peaking(frequency: 1000, gain: 6, sampleRate: 48_000)
        // Ganho em w0: |H(e^jw0)| deve ser ~6 dB.
        let w = 2 * Double.pi * 1000 / 48_000
        func mag(_ b0: Double, _ b1: Double, _ b2: Double) -> Double {
            let re = b0 + b1 * cos(w) + b2 * cos(2 * w)
            let im = -b1 * sin(w) - b2 * sin(2 * w)
            return (re * re + im * im).squareRoot()
        }
        let db = 20 * log10(mag(c[0], c[1], c[2]) / mag(1, c[3], c[4]))
        #expect(abs(db - 6) < 0.01)
    }

    @Test func editingABandMakesItCustom() {
        let eq = Equalizer(defaults: UserDefaults(suiteName: "eq-test-\(UUID())")!)
        #expect(!eq.enabled)
        eq.apply(Equalizer.presets[1])
        #expect(eq.enabled && eq.presetName == "Graves")
        eq.setGain(9, 3)
        #expect(eq.presetName == Equalizer.custom)
        eq.setGain(9, 0)
        #expect(eq.presetName == "Graves")
        #expect(eq.shared.read().gains == Equalizer.presets[1].gains)
    }
}
