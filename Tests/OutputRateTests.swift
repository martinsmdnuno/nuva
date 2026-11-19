import CoreAudio
import Foundation
import Testing
@testable import NuVa

/// Reads of the output device's sample rate. A machine with no output device (a CI runner)
/// has nothing to read, so each test returns early there.
struct OutputRateTests {
    @Test func deviceOffersItsOwnRate() throws {
        guard let device = CoreAudioDevice.defaultOutput(), let rate = device.currentSampleRate() else { return }
        let offered = device.availableSampleRates()
        #expect(!offered.isEmpty)
        #expect(offered.contains { $0.contains(rate) })
    }

    /// Writes to the hardware, so it runs only when asked:
    /// `TEST_RUNNER_NUVA_RATE_TRIAL=1 xcodebuild … test -only-testing:NuVaTests/OutputRateTests`.
    /// It answers one question of the plan: may the sandboxed app change the device's rate?
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NUVA_RATE_TRIAL"] == "1"))
    func sandboxedAppMaySetTheRate() async throws {
        let device = try #require(CoreAudioDevice.defaultOutput())
        let before = try #require(device.currentSampleRate())
        let other = try #require([44_100.0, 48_000, 88_200, 96_000].first { candidate in
            candidate != before && device.availableSampleRates().contains { $0.contains(candidate) }
        })
        #expect(device.setSampleRate(other) == noErr)
        try await waitForRate(other, on: device)
        #expect(device.setSampleRate(before) == noErr)
        try await waitForRate(before, on: device)
    }

    private func waitForRate(_ rate: Double, on device: CoreAudioDevice) async throws {
        for _ in 0..<50 where device.currentSampleRate() != rate {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(device.currentSampleRate() == rate)
    }
}
