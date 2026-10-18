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
        let source = try #require(store.addLocal(root))

        let browser = Browser(sources: store)
        let tracks = await browser.tracks(in: BrowserLocation(sourceID: source.id, path: "Tusk"))
        #expect(tracks.map(\.path) == ["Tusk/0 Intro.flac", "Tusk/CD 02/2 A.flac", "Tusk/CD 02/10 B.flac", "Tusk/CD 10/1 Z.flac"])

        // The source is remembered by another instance with the same defaults.
        #expect(SourceStore(defaults: defaults).sources.map(\.id) == [source.id])
    }
}
