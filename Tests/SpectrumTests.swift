import AVFoundation
import Testing
@testable import NuVa

struct SpectrumTests {
    /// Runs `seconds` of a sine through an analyzer, in stereo buffers of 1024 frames,
    /// and returns the last levels written.
    private func levels(sine frequency: Double, amplitude: Float, sampleRate: Double) throws -> [Float] {
        let analyzer = try #require(SpectrumAnalyzer(sampleRate: sampleRate))
        let shared = SpectrumShared()
        let frames = 1024
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { list.unsafeMutablePointer.deallocate() }
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { left.deallocate(); right.deallocate() }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: right)

        var n = 0
        for _ in 0..<20 {
            for j in 0..<frames {
                let v = amplitude * Float(sin(2 * Double.pi * frequency * Double(n + j) / sampleRate))
                left[j] = v
                right[j] = v
            }
            n += frames
            analyzer.process(list, frames: frames, end: Double(n) / sampleRate, into: shared)
        }
        return try #require(shared.levels(at: Double(n) / sampleRate, tolerance: 1))
    }

    @Test(arguments: [44_100.0, 96_000.0, 192_000.0])
    func fullScaleSineReadsZeroInItsBand(sampleRate: Double) throws {
        let l = try levels(sine: 1000, amplitude: 1, sampleRate: sampleRate)
        // 1 kHz is band 5.
        #expect(abs(l[5]) < 1.5)
        for b in [0, 1, 2, 8, 9] { #expect(l[b] < -40) }
    }

    @Test func levelFollowsAmplitude() throws {
        let l = try levels(sine: 125, amplitude: 0.1, sampleRate: 48_000)
        #expect(abs(l[2] + 20) < 1.5)
    }

    @Test func lookupIsByTrackTime() {
        let shared = SpectrumShared()
        let a: [Float] = Array(repeating: -10, count: SpectrumShared.bands)
        let b: [Float] = Array(repeating: -30, count: SpectrumShared.bands)
        a.withUnsafeBufferPointer { shared.write(time: 10, levels: $0) }
        b.withUnsafeBufferPointer { shared.write(time: 12, levels: $0) }
        #expect(shared.levels(at: 10.05) == a)
        #expect(shared.levels(at: 11.95) == b)
        #expect(shared.levels(at: 11) == nil)
    }
}
