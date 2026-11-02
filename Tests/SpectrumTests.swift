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

    @Test func stereoLevelsAreStoredWithTheBands() {
        let shared = SpectrumShared()
        let bands: [Float] = Array(repeating: -20, count: SpectrumShared.bands)
        let stereo = SIMD4<Float>(-18, -24, -6, -9)
        bands.withUnsafeBufferPointer { shared.write(time: 5, levels: $0, stereo: stereo) }
        #expect(shared.stereo(at: 5.05) == stereo)
        #expect(shared.stereo(at: 7) == nil)
    }

    @Test func fineBandsCoverTwentyHertzToTwentyKilohertz() {
        let centres = SpectrumShared.fineCentres
        #expect(centres.count == 28)
        #expect(centres.first! > 20 && centres.first! < 30)
        #expect(centres.last! > 15_000 && centres.last! < 20_000)
    }

    @Test func fineBandsFollowTheSignal() {
        let shared = SpectrumShared()
        let bands: [Float] = Array(repeating: -20, count: SpectrumShared.bands)
        let fine: [Float] = (0..<SpectrumShared.fineBands).map { -Float($0) }
        bands.withUnsafeBufferPointer { b in fine.withUnsafeBufferPointer { shared.write(time: 3, levels: b, fine: $0) } }
        #expect(shared.fineLevels(at: 3) == fine)
    }

    @Test func sineLandsInItsFineBandAndSetsTheStereoLevel() throws {
        let sampleRate = 48_000.0
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
                left[j] = 0.1 * Float(sin(2 * Double.pi * 1000 * Double(n + j) / sampleRate))
                right[j] = 0  // silent right channel
            }
            n += frames
            analyzer.process(list, frames: frames, end: Double(n) / sampleRate, into: shared)
        }
        let time = Double(n) / sampleRate
        let fine = try #require(shared.fineLevels(at: time, tolerance: 1))
        let loudest = fine.indices.max { fine[$0] < fine[$1] }!
        let centre = SpectrumShared.fineCentres[loudest]
        #expect(centre > 800 && centre < 1250)
        let stereo = try #require(shared.stereo(at: time, tolerance: 1))
        // A sine of amplitude 0.1: RMS -23 dBFS, peak -20 dBFS; the right channel is silent.
        #expect(abs(stereo[0] + 23) < 0.5)
        #expect(abs(stereo[2] + 20) < 0.5)
        #expect(stereo[1] < -100)
    }
}
