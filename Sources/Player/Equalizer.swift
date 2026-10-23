import Accelerate
import AVFoundation
import MediaToolbox
import Observation
import os

/// Equalizer preset: gain in dB for each of the 10 bands.
struct EQPreset: Identifiable, Sendable {
    let name: String
    let gains: [Float]
    var id: String { name }
}

/// 10-band equalizer. Runs inside the AVPlayer, in an MTAudioProcessingTap
/// per track: the sound is still the native engine's, just filtered.
@MainActor
@Observable
final class Equalizer {
    nonisolated static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let range: ClosedRange<Float> = -12...12
    static let custom = "Personalizado"

    /// A preset's name in the app's language. The Portuguese names are the key (and what gets saved).
    nonisolated static func displayName(_ name: String) -> String {
        Bundle.main.localizedString(forKey: name, value: name, table: nil)
    }

    static let presets: [EQPreset] = [
        EQPreset(name: "Plano", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Graves", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Agudos", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(name: "Voz", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(name: "Loudness", gains: [6, 4, 2, 0, -1, -1, 0, 2, 4, 5]),
        EQPreset(name: "Rock", gains: [4, 3, 1, -1, -2, -1, 1, 3, 4, 4]),
        EQPreset(name: "Clássica", gains: [3, 2, 1, 0, 0, 0, -1, 1, 2, 3]),
        EQPreset(name: "Noite", gains: [3, 2, 1, 0, 0, 0, -1, -2, -3, -4]),
    ]

    var enabled: Bool {
        didSet { push() }
    }
    private(set) var gains: [Float]
    /// Name of the active preset, or "Personalizado" after changing a band.
    private(set) var presetName: String

    /// Gains shared with the audio thread.
    nonisolated let shared: EQShared
    /// Band levels measured by the same tap, for the spectrum meter.
    nonisolated let spectrum = SpectrumShared()
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.array(forKey: "eq.gains") as? [Float]
        let gains = saved?.count == Self.frequencies.count ? saved! : Self.presets[0].gains
        let enabled = defaults.bool(forKey: "eq.enabled")
        self.gains = gains
        self.enabled = enabled
        self.presetName = defaults.string(forKey: "eq.preset") ?? Self.presets[0].name
        self.shared = EQShared(gains: gains, enabled: enabled)
    }

    func apply(_ preset: EQPreset) {
        gains = preset.gains
        presetName = preset.name
        enabled = true
    }

    func setGain(_ band: Int, _ db: Float) {
        gains[band] = min(max((db * 2).rounded() / 2, Self.range.lowerBound), Self.range.upperBound)
        presetName = Self.presets.first { $0.gains == gains }?.name ?? Self.custom
        if !enabled { enabled = true } else { push() }
    }

    private func push() {
        shared.set(gains: gains, enabled: enabled)
        defaults.set(gains, forKey: "eq.gains")
        defaults.set(enabled, forKey: "eq.enabled")
        defaults.set(presetName, forKey: "eq.preset")
    }

    /// Attaches the equalizer to the item's audio track, before playing.
    func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
              let tap = EQTap.make(shared, spectrum: spectrum) else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }
}

/// State read by the audio thread. `version` changes on every edit so the tap rebuilds its filters.
final class EQShared: Sendable {
    struct State: Sendable {
        var gains: [Float]
        var enabled: Bool
        var version: Int
    }

    private let state: OSAllocatedUnfairLock<State>

    init(gains: [Float], enabled: Bool) {
        state = OSAllocatedUnfairLock(initialState: State(gains: gains, enabled: enabled, version: 0))
    }

    func read() -> State { state.withLock { $0 } }

    func set(gains: [Float], enabled: Bool) {
        state.withLock { $0 = State(gains: gains, enabled: enabled, version: $0.version + 1) }
    }
}

/// The tap: 10 cascaded peaking (RBJ) filters per channel, with negative pre-gain to avoid clipping.
/// After the filters it measures the bands for the spectrum meter, while one is on screen.
final class EQTap: @unchecked Sendable {
    private let shared: EQShared
    private let spectrum: SpectrumShared
    private var analyzer: SpectrumAnalyzer?
    private var sampleRate: Double = 44_100
    private var supported = false
    private var filters: [vDSP.Biquad<Float>] = []
    private var preGain: Float = 1
    private var appliedVersion = -1

    private init(shared: EQShared, spectrum: SpectrumShared) {
        self.shared = shared
        self.spectrum = spectrum
    }

    static func make(_ shared: EQShared, spectrum: SpectrumShared) -> MTAudioProcessingTap? {
        let context = Unmanaged.passRetained(EQTap(shared: shared, spectrum: spectrum)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<EQTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                EQTap.from(tap).prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                var range = CMTimeRange.invalid
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, &range, framesOut) == noErr
                else { return }
                EQTap.from(tap).process(buffers, frames: Int(framesOut.pointee), range: range)
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr
        else {
            Unmanaged<EQTap>.fromOpaque(context).release()
            return nil
        }
        return tap
    }

    private static func from(_ tap: MTAudioProcessingTap) -> EQTap {
        Unmanaged<EQTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    private func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate
        // The AVPlayer delivers non-interleaved Float32 (one buffer per channel); any other format passes unfiltered.
        supported = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            && format.mBitsPerChannel == 32
        appliedVersion = -1
        analyzer = supported ? SpectrumAnalyzer(sampleRate: sampleRate) : nil
    }

    private func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, range: CMTimeRange) {
        guard supported else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        filter(buffers)
        if let analyzer, range.isValid, spectrum.isWatched {
            analyzer.process(buffers, frames: frames, end: range.end.seconds, into: spectrum)
        }
    }

    private func filter(_ buffers: UnsafeMutableAudioBufferListPointer) {
        let state = shared.read()
        guard state.enabled else { return }
        if state.version != appliedVersion || filters.count != buffers.count {
            rebuild(state.gains, channels: buffers.count)
            appliedVersion = state.version
        }
        for (i, buffer) in buffers.enumerated() where i < filters.count {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let samples = UnsafeMutableBufferPointer(start: data, count: Int(buffer.mDataByteSize) / 4)
            var output = samples
            vDSP.multiply(preGain, samples, result: &output)
            filters[i].apply(input: samples, output: &output)
        }
    }

    private func rebuild(_ gains: [Float], channels: Int) {
        let coefficients = zip(Equalizer.frequencies, gains).flatMap { f, g in
            Self.peaking(frequency: f, gain: Double(g), sampleRate: sampleRate)
        }
        filters = (0..<channels).compactMap { _ in
            vDSP.Biquad(coefficients: coefficients, channelCount: 1, sectionCount: vDSP_Length(gains.count), ofType: Float.self)
        }
        preGain = pow(10, -max(0, gains.max() ?? 0) / 20)
    }

    /// Normalized [b0, b1, b2, a1, a2] coefficients of a peaking filter (Audio EQ Cookbook, Q 1.41).
    static func peaking(frequency: Double, gain: Double, sampleRate: Double) -> [Double] {
        guard gain != 0, frequency < sampleRate / 2 else { return [1, 0, 0, 0, 0] }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * 1.41)
        let a0 = 1 + alpha / a
        return [(1 + alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha / a) / a0]
    }
}
