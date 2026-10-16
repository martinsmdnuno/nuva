import AVFoundation
import Testing
@testable import NuVa

@MainActor
struct PlayerTests {
    /// Gera FLACs curtos a 44.1 kHz numa pasta temporária.
    private func makeFlacs(_ count: Int, seconds: Double) throws -> (URL, [Entry]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let sourceID = UUID()
        var entries: [Entry] = []
        for i in 1...count {
            let name = String(format: "%02d - Tom %d.flac", i, i)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2, AVEncoderBitDepthHintKey: 16,
            ]
            let file = try AVAudioFile(forWriting: dir.appendingPathComponent(name), settings: settings)
            let frames = AVAudioFrameCount(seconds * 44100)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            for ch in 0..<2 {
                for f in 0..<Int(frames) {
                    buffer.floatChannelData![ch][f] = Float(sin(Double(f) * 2 * .pi * 220 * Double(i) / 44100)) * 0.1
                }
            }
            try file.write(from: buffer)
            entries.append(Entry(sourceID: sourceID, path: "Álbum/\(name)", name: name, kind: .track))
        }
        return (dir, entries)
    }

    private func makePlayer(_ dir: URL) -> PlayerController {
        let player = PlayerController { entry in dir.appendingPathComponent(entry.name) }
        player.volume = 0
        return player
    }

    private func wait(
        _ timeout: Double = 5, sourceLocation: SourceLocation = #_sourceLocation, until condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("Tempo esgotado", sourceLocation: sourceLocation)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func playsAndAdvancesThroughQueue() async throws {
        let (dir, entries) = try makeFlacs(2, seconds: 1.5)
        defer { try? FileManager.default.removeItem(at: dir) }
        let player = makePlayer(dir)

        player.setQueue(entries)
        try await wait { player.isPlaying && player.duration > 1 }
        #expect(abs(player.duration - 1.5) < 0.1)
        try await wait { player.formatLabel.contains("/") }
        #expect(player.formatLabel.hasPrefix("FLAC ") && player.formatLabel.hasSuffix("/44.1"))
        #expect(player.current?.entry == entries[0])

        try await wait { player.current?.entry == entries[1] }
        try await wait { !player.isPlaying }
        #expect(player.current?.entry == entries[1])
    }

    @Test func repeatAllWrapsAround() async throws {
        let (dir, entries) = try makeFlacs(2, seconds: 1)
        defer { try? FileManager.default.removeItem(at: dir) }
        let player = makePlayer(dir)
        player.repeatMode = .all

        player.setQueue(entries, startAt: 1)
        try await wait { player.isPlaying }
        try await wait { player.current?.entry == entries[0] }
        #expect(player.isPlaying)
    }

    @Test func transportControls() async throws {
        let (dir, entries) = try makeFlacs(3, seconds: 8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let player = makePlayer(dir)

        player.setQueue(entries)
        try await wait { player.isPlaying && player.duration > 7 }

        player.seek(to: 5)
        try await wait { player.currentTime >= 5 }

        player.previous()  // passou 3 s: volta ao início da mesma faixa
        try await wait { player.currentTime < 1 }
        #expect(player.current?.entry == entries[0])

        player.next()
        try await wait { player.current?.entry == entries[1] && player.isPlaying }
        player.previous()
        try await wait { player.current?.entry == entries[0] && player.isPlaying }

        player.togglePlayPause()
        try await wait { !player.isPlaying }
        player.togglePlayPause()
        try await wait { player.isPlaying }
        player.pause()
    }

    @Test func queueEditsKeepCurrentTrack() async throws {
        let (dir, entries) = try makeFlacs(4, seconds: 8)
        defer { try? FileManager.default.removeItem(at: dir) }
        let player = makePlayer(dir)

        player.setQueue(Array(entries.prefix(3)), startAt: 1)
        try await wait { player.isPlaying }
        player.append([entries[3]])
        player.move(fromOffsets: [1], toOffset: 4)
        #expect(player.queue.map(\.entry) == [entries[0], entries[2], entries[3], entries[1]])
        #expect(player.current?.entry == entries[1])

        player.remove(atOffsets: [3])  // remove a atual: segue para nenhuma (é a última)
        #expect(player.queue.count == 3)
        player.remove(atOffsets: [0])
        #expect(player.queue.map(\.entry) == [entries[2], entries[3]])

        player.shuffle = true
        player.setQueue(entries)
        #expect(player.current?.entry == entries[0])
        player.pause()
    }

    /// Ficheiro real, se existir (copiado à mão para o contentor da app).
    @Test func realFlacIfPresent() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("real.flac")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let player = PlayerController { _ in url }
        player.volume = 0
        player.setQueue([Entry(sourceID: UUID(), path: "real.flac", name: "real.flac", kind: .track)])
        try await wait { player.isPlaying && player.duration > 0 && player.formatLabel.contains("/") }
        print("real.flac:", player.formatLabel, player.duration)
        #expect(player.formatLabel == "FLAC 24/48")
        player.pause()
    }
}
