import Foundation
import Testing
@testable import NuVa

@MainActor
struct BrowserTests {
    @Test func tracksIncludeSubfoldersInNaturalOrder() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for (cd, names) in [("CD 10", ["1 Z.flac"]), ("CD 02", ["10 B.flac", "2 A.flac"])] {
            let dir = root.appendingPathComponent("Tusk/\(cd)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for n in names { fm.createFile(atPath: dir.appendingPathComponent(n).path, contents: nil) }
        }
        fm.createFile(atPath: root.appendingPathComponent("Tusk/0 Intro.flac").path, contents: nil)

        let suite = "browser-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SourceStore(defaults: defaults)
        let source = try store.addLocal(root)

        let browser = Browser(sources: store)
        let tracks = await browser.tracks(in: BrowserLocation(sourceID: source.id, path: "Tusk"))
        #expect(tracks.map(\.path) == ["Tusk/0 Intro.flac", "Tusk/CD 02/2 A.flac", "Tusk/CD 02/10 B.flac", "Tusk/CD 10/1 Z.flac"])

        // The source is remembered by another instance with the same defaults.
        #expect(SourceStore(defaults: defaults).sources.map(\.id) == [source.id])
    }

    @Test func removingASourceTakesItsTracksOutOfTheQueue() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Álbum"), withIntermediateDirectories: true)
        for n in ["1 A.flac", "2 B.flac"] {
            fm.createFile(atPath: root.appendingPathComponent("Álbum/\(n)").path, contents: nil)
        }
        let suite = "browser-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let source = try model.sources.addLocal(root)
        let tracks = await model.browser.tracks(in: BrowserLocation(sourceID: source.id, path: "Álbum"))
        model.player.append(tracks)
        model.browser.open(BrowserLocation(sourceID: source.id, path: "Álbum"))

        model.removeSource(source.id)
        #expect(model.player.queue.isEmpty)
        #expect(model.browser.location == nil)
        #expect(model.sources.source(source.id) == nil)
    }

    /// A folder that can't be listed is said, not played as an album with tracks missing.
    @Test func foldersThatDoNotOpenAreCountedAndReported() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Tusk/CD 02").path)
            try? fm.removeItem(at: root)
        }
        for cd in ["CD 01", "CD 02"] {
            let dir = root.appendingPathComponent("Tusk/\(cd)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: dir.appendingPathComponent("1 A.flac").path, contents: nil)
        }
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("Tusk/CD 02").path)

        let suite = "browser-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let source = try model.sources.addLocal(root)

        let found = await model.browser.collect(in: BrowserLocation(sourceID: source.id, path: "Tusk"))
        #expect(found.tracks.map(\.path) == ["Tusk/CD 01/1 A.flac"])
        #expect(found.unreadable == 1)

        await model.enqueue(Entry(sourceID: source.id, path: "Tusk", name: "Tusk", kind: .folder))
        #expect(model.player.queue.count == 1)
        #expect(model.notice?.message == String(localized: "Algumas pastas não abriram"))

        await model.playFolder(BrowserLocation(sourceID: source.id, path: "Gone"))
        #expect(model.notice?.message == String(localized: "Não foi possível abrir a pasta"))
    }
}
