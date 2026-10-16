import Accelerate
import AVFoundation
import MediaToolbox
import Observation
import os

/// Preset do equalizador: ganho em dB para cada uma das 10 bandas.
struct EQPreset: Identifiable, Sendable {
    let name: String
    let gains: [Float]
    var id: String { name }
}

/// Equalizador de 10 bandas. Corre dentro do AVPlayer, num MTAudioProcessingTap
/// por faixa: o som continua a ser o do motor nativo, só filtrado.
@MainActor
@Observable
final class Equalizer {
    nonisolated static let frequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let range: ClosedRange<Float> = -12...12
    static let custom = "Personalizado"

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
    /// Nome do preset ativo, ou "Personalizado" depois de mexer numa banda.
    private(set) var presetName: String

    /// Ganhos partilhados com a thread de áudio.
    nonisolated let shared: EQShared
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

    /// Liga o equalizador à faixa de áudio do item, antes de tocar.
    func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
              let tap = EQTap.make(shared) else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }
}

/// Estado lido pela thread de áudio. `version` muda a cada alteração para o tap refazer os filtros.
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

/// O tap: 10 filtros peaking (RBJ) em cascata por canal, com pré-ganho negativo para não saturar.
final class EQTap: @unchecked Sendable {
    private let shared: EQShared
    private var sampleRate: Double = 44_100
    private var supported = false
    private var filters: [vDSP.Biquad<Float>] = []
    private var preGain: Float = 1
    private var appliedVersion = -1

    private init(shared: EQShared) {
        self.shared = shared
    }

    static func make(_ shared: EQShared) -> MTAudioProcessingTap? {
        let context = Unmanaged.passRetained(EQTap(shared: shared)).toOpaque()
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
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr
                else { return }
                EQTap.from(tap).process(buffers)
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
        // O AVPlayer entrega Float32 não intercalado (um buffer por canal); outro formato passa sem filtro.
        supported = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            && format.mBitsPerChannel == 32
        appliedVersion = -1
    }

    private func process(_ list: UnsafeMutablePointer<AudioBufferList>) {
        guard supported else { return }
        let state = shared.read()
        guard state.enabled else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
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

    /// Coeficientes [b0, b1, b2, a1, a2] normalizados de um filtro peaking (Audio EQ Cookbook, Q 1,41).
    static func peaking(frequency: Double, gain: Double, sampleRate: Double) -> [Double] {
        guard gain != 0, frequency < sampleRate / 2 else { return [1, 0, 0, 0, 0] }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * 1.41)
        let a0 = 1 + alpha / a
        return [(1 + alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha / a) / a0]
    }
}
