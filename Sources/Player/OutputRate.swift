import CoreAudio
import Foundation

/// What `OutputRate` needs from an output device: `CoreAudioDevice` in the app, a fake in tests.
protocol RateSettable {
    /// Stable across replugging, unlike the device's ID. nil: the device can't be remembered.
    var uid: String? { get }
    /// False for AirPlay and Bluetooth, whose rate is not NuVa's to set.
    var followsTracks: Bool { get }
    func currentSampleRate() -> Double?
    func availableSampleRates() -> [ClosedRange<Double>]
    @discardableResult func setSampleRate(_ rate: Double) -> OSStatus
}

extension CoreAudioDevice: RateSettable {
    var followsTracks: Bool { !isAirPlay && !isBluetooth }
}

/// Sets a wired output to the track's sample rate, remembers the rate each device had before
/// the first change and puts it back on quit. Plan in docs/plans/dac-sample-rate.md.
@MainActor
final class OutputRate {
    enum Outcome: Equatable {
        /// Not NuVa's to set (AirPlay, Bluetooth), or the device says nothing about its rates.
        case leftAlone
        /// The device is already at the best rate it offers for this track.
        case unchanged(Double)
        /// The device was asked for this rate; it reports the change a moment later.
        case asked(Double)
        /// The device said no; playback goes on, resampled by macOS.
        case refused(Double, OSStatus)
    }

    /// By device UID: the rate before NuVa's first change, and the last rate NuVa asked for.
    private var original: [String: Double] = [:]
    private var asked: [String: Double] = [:]
    private let find: (String) -> (any RateSettable)?

    init(find: @escaping (String) -> (any RateSettable)? = { CoreAudioDevice(uid: $0) }) {
        self.find = find
    }

    @discardableResult
    func match(track: Double, on device: any RateSettable) -> Outcome {
        guard device.followsTracks, let now = device.currentSampleRate(),
              let rate = Self.choose(track: track, available: device.availableSampleRates())
        else { return .leftAlone }
        guard !Self.same(rate, now) else { return .unchanged(now) }
        let status = device.setSampleRate(rate)
        guard status == noErr else { return .refused(rate, status) }
        if let uid = device.uid {
            if original[uid] == nil { original[uid] = now }
            asked[uid] = rate
        }
        return .asked(rate)
    }

    /// Puts each device back at the rate it had. A device that is gone, or whose rate someone
    /// else changed after NuVa did, is left as it is.
    func restore() {
        for (uid, rate) in original {
            guard let device = find(uid), let now = device.currentSampleRate(),
                  let mine = asked[uid], Self.same(now, mine), !Self.same(now, rate) else { continue }
            device.setSampleRate(rate)
        }
        original = [:]
        asked = [:]
    }

    /// The rate to ask a device for, given the ranges it offers; nil if it offers none.
    /// In order: the track's own rate; its lowest whole multiple (44.1 → 88.2); the nearest
    /// rate above it; and for a track above all the device has, the highest rate that divides
    /// it whole (176.4 → 88.2, not 96), else the highest there is.
    nonisolated static func choose(track: Double, available: [ClosedRange<Double>]) -> Double? {
        guard track > 0, let top = available.map(\.upperBound).max() else { return nil }
        func offered(_ rate: Double) -> Bool {
            available.contains { $0.lowerBound - tolerance <= rate && rate <= $0.upperBound + tolerance }
        }
        if offered(track) { return track }
        var multiple = track * 2
        while multiple <= top + tolerance {
            if offered(multiple) { return multiple }
            multiple += track
        }
        if let higher = available.map(\.lowerBound).filter({ $0 > track }).min() { return higher }
        var divisor = 2.0
        while track / divisor >= 8_000 {
            if offered(track / divisor) { return track / divisor }
            divisor += 1
        }
        return top
    }

    /// Rates are whole numbers of Hz; anything closer than this is the same rate.
    private nonisolated static let tolerance = 0.5

    private nonisolated static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) < tolerance }
}
