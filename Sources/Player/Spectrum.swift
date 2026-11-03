import Accelerate
import AVFoundation
import os

/// Levels of the equalizer's 10 bands, measured in the audio tap after the equalizer, so the
/// meter shows what is heard. Each measurement carries its time in the track: the tap runs ahead
/// of the speakers (seconds ahead over AirPlay), and the display asks for the moment being played.
final class SpectrumShared: Sendable {
    nonisolated static let bands = Equalizer.frequencies.count
    /// The ambient Spectrum face's finer bands: 28, evenly spaced in log frequency from 20 Hz to 20 kHz.
    nonisolated static let fineBands = 28
    nonisolated static let fineCentres: [Double] = (0..<fineBands).map { i in
        20 * pow(1000, (Double(i) + 0.5) / Double(fineBands))
    }
    /// About 4 s of measurements at 60 a second, more than AirPlay's buffer.
    nonisolated static let capacity = 256

    private struct State {
        var times: [Double]
        var levels: [Float]
        var fine: [Float]
        /// Per measurement: RMS left, RMS right, peak left, peak right, in dBFS.
        var stereo: [SIMD4<Float>]
        var next = 0
        /// Meters on screen. With none, the tap doesn't measure.
        var watchers = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init() {
        state = OSAllocatedUnfairLock(initialState: State(
            times: Array(repeating: -1, count: Self.capacity),
            levels: Array(repeating: 0, count: Self.capacity * Self.bands),
            fine: Array(repeating: -120, count: Self.capacity * Self.fineBands),
            stereo: Array(repeating: SIMD4(repeating: -120), count: Self.capacity)))
    }

    var isWatched: Bool { state.withLock { $0.watchers > 0 } }

    func watch(_ on: Bool) {
        state.withLock { $0.watchers = max(0, $0.watchers + (on ? 1 : -1)) }
    }

    /// Audio thread: band levels in dBFS measured around `time` (seconds in the track).
    /// `stereo`: RMS left, RMS right, peak left, peak right, in dBFS (a mono source repeats its channel).
    func write(
        time: Double, levels: UnsafeBufferPointer<Float>, stereo: SIMD4<Float> = SIMD4(repeating: -120),
        fine: UnsafeBufferPointer<Float>? = nil
    ) {
        // Unchecked: the pointer is only read inside the lock, on the calling thread.
        state.withLockUnchecked { s in
            let i = s.next
            s.times[i] = time
            for b in 0..<Self.bands { s.levels[i * Self.bands + b] = levels[b] }
            s.stereo[i] = stereo
            for b in 0..<Self.fineBands { s.fine[i * Self.fineBands + b] = fine?[b] ?? -120 }
            s.next = (i + 1) % Self.capacity
        }
    }

    /// Levels at `time`, between the measurements on either side of it, or nil when none is within
    /// `tolerance` (paused, seeking). Blending them keeps the meters moving smoothly between measurements.
    func levels(at time: Double, tolerance: Double = 0.15) -> [Float]? {
        state.withLock { s in
            Self.bracket(in: s, at: time, tolerance: tolerance).map { Self.blend(s.levels, width: Self.bands, $0) }
        }
    }

    /// The 28 fine bands in dBFS at `time`.
    func fineLevels(at time: Double, tolerance: Double = 0.15) -> [Float]? {
        state.withLock { s in
            Self.bracket(in: s, at: time, tolerance: tolerance).map { Self.blend(s.fine, width: Self.fineBands, $0) }
        }
    }

    /// Left and right levels (RMS, RMS, peak, peak in dBFS) at `time`.
    func stereo(at time: Double, tolerance: Double = 0.15) -> SIMD4<Float>? {
        state.withLock { s in
            Self.bracket(in: s, at: time, tolerance: tolerance).map { b in
                s.stereo[b.before] + (s.stereo[b.after] - s.stereo[b.before]) * b.weight
            }
        }
    }

    /// The measurements just before and just after `time` (the same one at either end of the buffer),
    /// and how far `time` lies from the first towards the second, 0 to 1.
    private static func bracket(in s: State, at time: Double, tolerance: Double) -> (before: Int, after: Int, weight: Float)? {
        var before: Int?, after: Int?
        var early = -Double.infinity, late = Double.infinity
        for (i, t) in s.times.enumerated() where t >= 0 && abs(t - time) <= tolerance {
            if t <= time, t > early { before = i; early = t }
            if t >= time, t < late { after = i; late = t }
        }
        switch (before, after) {
        case let (b?, a?): return (b, a, late > early ? Float((time - early) / (late - early)) : 0)
        case let (b?, nil): return (b, b, 0)
        case let (nil, a?): return (a, a, 0)
        case (nil, nil): return nil
        }
    }

    private static func blend(_ values: [Float], width: Int, _ b: (before: Int, after: Int, weight: Float)) -> [Float] {
        (0..<width).map { k in
            let x = values[b.before * width + k]
            return x + (values[b.after * width + k] - x) * b.weight
        }
    }
}

/// Audio thread, one per tap: keeps the last samples in mono, and about 60 times a second
/// sums an FFT's power into octave bands centred on the equalizer's frequencies.
final class SpectrumAnalyzer {
    private let sampleRate: Double
    private let size: Int
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let bandBins: [Range<Int>]
    private let fineBins: [Range<Int>]
    /// Power of a full-scale sine summed over its bins, with this window and vDSP's scaling.
    private let fullScale: Float

    private var history: [Float]
    private var head = 0
    private var pending = 0
    private var frame: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var power: [Float]
    private var levels: [Float]
    private var fine: [Float]
    /// Left and right since the last measurement: sum of squares and highest absolute sample.
    private var squares = SIMD2<Float>(repeating: 0)
    private var highs = SIMD2<Float>(repeating: 0)
    private var counted = 0

    init?(sampleRate: Double) {
        // About 46 ms of sound, so the 32 Hz band gets at least one bin at any rate.
        let size = sampleRate <= 48_000 ? 2048 : sampleRate <= 96_000 ? 4096 : 8192
        guard let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size))), radix: .radix2, ofType: DSPSplitComplex.self)
        else { return nil }
        self.sampleRate = sampleRate
        self.size = size
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        let binWidth = sampleRate / Double(size)
        bandBins = Equalizer.frequencies.map { f in
            let lo = max(1, Int((f / 2.squareRoot() / binWidth).rounded()))
            let hi = min(size / 2, max(lo + 1, Int((f * 2.squareRoot() / binWidth).rounded())))
            return lo ..< max(lo, hi)
        }
        // Fine bands: edges halfway (in log frequency) between centres. The lowest share bins,
        // since a bin is 23 Hz wide at 48 kHz; at least one bin each.
        let ratio = pow(1000, 0.5 / Double(SpectrumShared.fineBands))
        fineBins = SpectrumShared.fineCentres.map { f in
            let lo = max(1, Int((f / ratio / binWidth).rounded(.down)))
            let hi = min(size / 2, max(lo + 1, Int((f * ratio / binWidth).rounded(.up))))
            return lo ..< max(lo, hi)
        }
        fine = Array(repeating: -120, count: SpectrumShared.fineBands)
        fullScale = 0.375 * Float(size) * Float(size)
        history = Array(repeating: 0, count: size)
        frame = Array(repeating: 0, count: size)
        real = Array(repeating: 0, count: size / 2)
        imag = Array(repeating: 0, count: size / 2)
        power = Array(repeating: 0, count: size / 2)
        levels = Array(repeating: -120, count: Equalizer.frequencies.count)
    }

    /// Adds the buffer (non-interleaved Float32) and measures every 1/60 s of it, writing each
    /// measurement to `shared` with its own time. `end` is the track time at the end of the buffer.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int, end: Double, into shared: SpectrumShared) {
        // Runs on the audio thread: no allocation, vectorised. Left and right are the first two
        // channels (a mono file repeats its only one); the mono mix for the bands is their average.
        guard buffers.count > 0, frames > 0, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? left : left
        // The player hands over blocks of up to several thousand frames (about 1/10 s): measuring
        // once per block would move the meters in steps.
        let hop = max(1, Int(sampleRate / 60))
        var offset = 0
        while offset < frames {
            let run = min(frames - offset, max(1, hop - pending))
            add(left + offset, right + offset, frames: run)
            offset += run
            pending += run
            guard pending >= hop else { continue }
            pending = 0
            measure()
            let rms = (squares / Float(max(counted, 1))).squareRoot()
            let stereo = SIMD4(Self.decibels(rms[0]), Self.decibels(rms[1]), Self.decibels(highs[0]), Self.decibels(highs[1]))
            squares = .zero
            highs = .zero
            counted = 0
            // The bands are centred half a window back; the levels cover the last 1/60 s.
            let time = end - Double(frames - offset) / sampleRate - Double(size / 2) / sampleRate
            levels.withUnsafeBufferPointer { bands in
                fine.withUnsafeBufferPointer {
                    shared.write(time: time, levels: bands, stereo: stereo, fine: $0)
                }
            }
        }
    }

    /// Adds `frames` samples of each channel to the level sums and the mono history.
    private func add(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        let n = vDSP_Length(frames)
        var sumL: Float = 0, sumR: Float = 0, highL: Float = 0, highR: Float = 0
        vDSP_svesq(left, 1, &sumL, n)
        vDSP_svesq(right, 1, &sumR, n)
        vDSP_maxmgv(left, 1, &highL, n)
        vDSP_maxmgv(right, 1, &highR, n)
        squares += SIMD2(sumL, sumR)
        highs = pointwiseMax(highs, SIMD2(highL, highR))

        // Into the ring buffer in at most two runs (up to its end, then from its start).
        var half: Float = 0.5
        var written = 0
        history.withUnsafeMutableBufferPointer { h in
            while written < frames {
                let run = min(frames - written, size - head)
                let destination = h.baseAddress! + head
                if left == right {
                    destination.update(from: left + written, count: run)
                } else {
                    vDSP_vasm(left + written, 1, right + written, 1, &half, destination, 1, vDSP_Length(run))
                }
                head = (head + run) % size
                written += run
            }
        }
        counted += frames
    }

    private static func decibels(_ amplitude: Float) -> Float {
        20 * log10(max(amplitude, 1e-6))
    }

    private func measure() {
        // Oldest sample first, windowed as it is copied (multiplying `frame` into itself would copy it).
        let tail = size - head
        frame.withUnsafeMutableBufferPointer { f in
            history.withUnsafeBufferPointer { h in
                window.withUnsafeBufferPointer { w in
                    vDSP_vmul(h.baseAddress! + head, 1, w.baseAddress!, 1, f.baseAddress!, 1, vDSP_Length(tail))
                    vDSP_vmul(h.baseAddress!, 1, w.baseAddress! + tail, 1, f.baseAddress! + tail, 1, vDSP_Length(head))
                }
            }
        }

        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                frame.withUnsafeBufferPointer { f in
                    f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                // Bin 0 holds DC and Nyquist packed together; no band uses it.
                power.withUnsafeMutableBufferPointer { p in
                    vDSP.squareMagnitudes(split, result: &p)
                }
            }
        }

        for (b, bins) in bandBins.enumerated() {
            let sum = bins.isEmpty ? 0 : vDSP.sum(power[bins])
            levels[b] = 10 * log10(max(sum / fullScale, 1e-12))
        }
        for (b, bins) in fineBins.enumerated() {
            let sum = bins.isEmpty ? 0 : vDSP.sum(power[bins])
            fine[b] = 10 * log10(max(sum / fullScale, 1e-12))
        }
    }
}
