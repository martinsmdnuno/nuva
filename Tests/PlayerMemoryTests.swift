import Foundation
import Testing
@testable import NuVa

@MainActor
struct PlayerMemoryTests {
    private func entries(_ source: UUID, _ names: [String]) -> [Entry] {
        names.map { Entry(sourceID: source, path: "Álbum/\($0)", name: $0, kind: .track) }
    }

    private func player() -> PlayerController {
        PlayerController { _ in URL(fileURLWithPath: "/nowhere") }
    }

    @Test func reopensWithTheQueueItsTrackAndTheSettings() throws {
        let suite = "memory-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = UUID()

        let first = player()
        let memory = PlayerMemory(player: first, defaults: defaults) { _ in true }
        first.restore(entries(source, ["1 A.flac", "2 B.flac", "3 C.flac"]), current: 1, position: 42, duration: 180)
        first.volume = 0.4
        first.repeatMode = .all
        memory.save(force: true)

        let second = player()
        _ = PlayerMemory(player: second, defaults: defaults) { _ in true }
        #expect(second.queue.map(\.entry.name) == ["1 A.flac", "2 B.flac", "3 C.flac"])
        #expect(second.current?.entry.name == "2 B.flac")
        #expect(second.currentTime == 42)
        #expect(second.duration == 180)
        #expect(second.volume == 0.4)
        #expect(second.repeatMode == .all)
        #expect(!second.shuffle)
        // Stopped: reopening the app never starts the music by itself.
        #expect(!second.isPlaying)
    }

    @Test func tracksOfASourceThatWentDoNotComeBack() throws {
        let suite = "memory-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (kept, gone) = (UUID(), UUID())

        let first = player()
        let memory = PlayerMemory(player: first, defaults: defaults) { _ in true }
        first.restore(
            entries(gone, ["1 CD.aiff"]) + entries(kept, ["1 A.flac", "2 B.flac"]), current: 2, position: 10, duration: 60)
        memory.save(force: true)

        let second = player()
        _ = PlayerMemory(player: second, defaults: defaults) { $0 == kept }
        #expect(second.queue.map(\.entry.name) == ["1 A.flac", "2 B.flac"])
        #expect(second.current?.entry.name == "2 B.flac")
        #expect(second.currentTime == 10)

        // The track it was on went with its source: the queue comes back with no track chosen.
        let third = player()
        _ = PlayerMemory(player: third, defaults: defaults) { $0 == gone }
        #expect(third.queue.map(\.entry.name) == ["1 CD.aiff"])
        #expect(third.current == nil)
        #expect(third.currentTime == 0)
    }
}
