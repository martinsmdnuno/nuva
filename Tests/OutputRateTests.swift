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

/// The choice of rate and the memory of what each device had, against a fake device.
@MainActor
struct OutputRateRulesTests {
    private let usual: [ClosedRange<Double>] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000].map { $0...$0 }

    @Test func choosesTheTracksOwnRate() {
        #expect(OutputRate.choose(track: 96_000, available: usual) == 96_000)
        // A device that offers a continuous range.
        #expect(OutputRate.choose(track: 88_200, available: [8_000...192_000]) == 88_200)
    }

    @Test func choosesTheLowestWholeMultiple() {
        #expect(OutputRate.choose(track: 44_100, available: [48_000, 88_200, 176_400].map { $0...$0 }) == 88_200)
        #expect(OutputRate.choose(track: 22_050, available: usual) == 44_100)
        // 3× when 2× is missing.
        #expect(OutputRate.choose(track: 32_000, available: [44_100, 96_000].map { $0...$0 }) == 96_000)
    }

    @Test func choosesTheNearestHigherThenTheHighest() {
        #expect(OutputRate.choose(track: 32_000, available: [44_100, 48_000].map { $0...$0 }) == 44_100)
        #expect(OutputRate.choose(track: 192_000, available: [44_100, 48_000].map { $0...$0 }) == 48_000)
    }

    @Test func choosesNothingWithoutRates() {
        #expect(OutputRate.choose(track: 44_100, available: []) == nil)
        #expect(OutputRate.choose(track: 0, available: usual) == nil)
    }

    @Test func setsOnceAndRestoresTheFirstRate() {
        let dac = FakeDevice(rate: 48_000, offered: usual)
        let output = OutputRate { _ in dac }
        #expect(output.match(track: 96_000, on: dac) == .asked(96_000))
        #expect(output.match(track: 96_000, on: dac) == .unchanged(96_000))
        #expect(output.match(track: 44_100, on: dac) == .asked(44_100))
        output.restore()
        #expect(dac.rate == 48_000)
        // Nothing left to restore.
        dac.rate = 96_000
        output.restore()
        #expect(dac.rate == 96_000)
    }

    @Test func leavesAirPlayAndBluetoothAlone() {
        let headphones = FakeDevice(rate: 48_000, offered: usual, followsTracks: false)
        let output = OutputRate { _ in headphones }
        #expect(output.match(track: 96_000, on: headphones) == .leftAlone)
        #expect(headphones.asked.isEmpty)
    }

    @Test func aRefusalChangesAndRemembersNothing() {
        let dac = FakeDevice(rate: 48_000, offered: usual, status: kAudioHardwareIllegalOperationError)
        let output = OutputRate { _ in dac }
        #expect(output.match(track: 96_000, on: dac) == .refused(96_000, kAudioHardwareIllegalOperationError))
        dac.status = noErr
        output.restore()
        #expect(dac.rate == 48_000)
        #expect(dac.asked == [96_000])
    }

    @Test func restoreDoesNotUndoSomeoneElsesChange() {
        let dac = FakeDevice(rate: 48_000, offered: usual)
        let output = OutputRate { _ in dac }
        output.match(track: 96_000, on: dac)
        dac.rate = 192_000   // the user, in Audio MIDI Setup
        output.restore()
        #expect(dac.rate == 192_000)
    }

    @Test func restoreSkipsADeviceThatIsGone() {
        let dac = FakeDevice(rate: 48_000, offered: usual)
        let output = OutputRate { _ in nil }
        output.match(track: 96_000, on: dac)
        output.restore()
        #expect(dac.rate == 96_000)
    }
}

private final class FakeDevice: RateSettable {
    let uid: String? = "fake"
    let followsTracks: Bool
    var rate: Double
    var status: OSStatus
    private(set) var asked: [Double] = []
    private let offered: [ClosedRange<Double>]

    init(rate: Double, offered: [ClosedRange<Double>], followsTracks: Bool = true, status: OSStatus = noErr) {
        self.rate = rate
        self.offered = offered
        self.followsTracks = followsTracks
        self.status = status
    }

    func currentSampleRate() -> Double? { rate }
    func availableSampleRates() -> [ClosedRange<Double>] { offered }

    func setSampleRate(_ rate: Double) -> OSStatus {
        asked.append(rate)
        if status == noErr { self.rate = rate }
        return status
    }
}
