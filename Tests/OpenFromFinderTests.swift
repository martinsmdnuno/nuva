import Foundation
import Testing
@testable import NuVa

/// What the Finder hands over: "Open With", a drop on the Dock icon or on the window.
@MainActor
struct OpenFromFinderTests {
    private func album(_ names: [String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("Fleetwood Mac/Tusk")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names { fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: nil) }
        return root
    }

    private func model() -> (AppModel, () -> Void) {
        let suite = "open-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppModel(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    @Test func aFolderOutsideEverySourceBecomesASourceAndPlays() async throws {
        let root = try album(["2 B.flac", "10 C.flac", "1 A.flac", "notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }

        await model.open([root.appendingPathComponent("Fleetwood Mac/Tusk")])
        #expect(model.sources.sources.map(\.name) == ["Tusk"])
        #expect(model.player.queue.map(\.entry.name) == ["1 A.flac", "2 B.flac", "10 C.flac"])
        #expect(model.player.current?.entry.name == "1 A.flac")
    }

    @Test func aTrackInsideASourcePlaysWithItsFolderQueued() async throws {
        let root = try album(["1 A.flac", "2 B.flac", "3 C.flac"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }
        let source = try model.sources.addLocal(root)

        await model.open([root.appendingPathComponent("Fleetwood Mac/Tusk/2 B.flac")])
        #expect(model.sources.sources.count == 1)
        #expect(model.player.queue.map(\.entry.path) == ["1 A.flac", "2 B.flac", "3 C.flac"].map { "Fleetwood Mac/Tusk/\($0)" })
        #expect(model.player.current?.entry.name == "2 B.flac")
        #expect(model.player.current?.entry.sourceID == source.id)
    }

    @Test func aFolderInsideASourceAddsNoSource() async throws {
        let root = try album(["1 A.flac"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }
        try model.sources.addLocal(root)

        await model.open([root.appendingPathComponent("Fleetwood Mac")])
        #expect(model.sources.sources.count == 1)
        #expect(model.player.queue.map(\.entry.path) == ["Fleetwood Mac/Tusk/1 A.flac"])
    }

    /// macOS hands over the file alone, so it plays alone, named by its real folders, and is never a source.
    @Test func tracksOutsideEverySourcePlayAlone() async throws {
        let root = try album(["2 B.flac", "1 A.flac", "cover.jpg"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }
        let dir = root.appendingPathComponent("Fleetwood Mac/Tusk")

        await model.open(["2 B.flac", "cover.jpg", "1 A.flac"].map { dir.appendingPathComponent($0) })
        #expect(model.sources.sources.isEmpty)
        #expect(model.player.queue.map(\.entry.name) == ["1 A.flac", "2 B.flac"])
        let entry = try #require(model.player.queue.first?.entry)
        #expect(entry.folderLine == "Fleetwood Mac · Tusk")
        #expect(try await model.sources.resolve(entry).lastPathComponent == "1 A.flac")
    }

    @Test func somethingThatIsNotMusicIsSaid() async throws {
        let root = try album(["notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }

        await model.open([root.appendingPathComponent("Fleetwood Mac/Tusk/notes.txt")])
        #expect(model.player.queue.isEmpty)
        #expect(model.notice != nil)
    }

    @Test func theDeepestSourceHoldsAPath() async throws {
        let root = try album(["1 A.flac"])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, done) = model()
        defer { done() }
        try model.sources.addLocal(root)
        let inner = try model.sources.addLocal(root.appendingPathComponent("Fleetwood Mac"))

        let found = try #require(model.sources.locate(root.appendingPathComponent("Fleetwood Mac/Tusk/1 A.flac")))
        #expect(found.source.id == inner.id)
        #expect(found.path == "Tusk/1 A.flac")
        #expect(model.sources.locate(FileManager.default.temporaryDirectory) == nil)
    }
}
