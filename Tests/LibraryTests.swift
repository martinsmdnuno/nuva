import Foundation
import Testing
@testable import NuVa

struct LibraryTests {
    private func entry(_ name: String, _ kind: Entry.Kind = .track) -> Entry {
        Entry(sourceID: UUID(), path: "Álbum/\(name)", name: name, kind: kind)
    }

    @Test func titleStripsNumberAndExtension() {
        #expect(entry("01 - Intro.flac").title == "Intro")
        #expect(entry("2. Remix (Extended).mp3").title == "Remix (Extended)")
        #expect(entry("10_Fim.m4a").title == "Fim")
        #expect(entry("1999.flac").title == "1999")
        #expect(entry("Sem número.wav").title == "Sem número")
    }

    @Test func naturalOrderFoldersFirst() {
        let sorted = [entry("10 b.flac"), entry("2 a.flac"), entry("CD2", .folder), entry("1 c.flac"), entry("CD1", .folder)]
            .naturallySorted().map(\.name)
        #expect(sorted == ["CD1", "CD2", "1 c.flac", "2 a.flac", "10 b.flac"])
    }

    @Test func localSourceListsPlayableFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = root.appendingPathComponent("Álbum")
        try FileManager.default.createDirectory(at: album.appendingPathComponent("Extras"), withIntermediateDirectories: true)
        for name in ["10 Dez.flac", "2 Dois.mp3", "capa.jpg", "notas.txt", ".oculto.flac"] {
            FileManager.default.createFile(atPath: album.appendingPathComponent(name).path, contents: Data())
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try LocalSource(id: UUID(), name: "Teste", bookmark: LocalSource.bookmark(for: root))
        #expect(try await source.list("").map(\.name) == ["Álbum"])
        let items = try await source.list("Álbum")
        #expect(items.map(\.name) == ["Extras", "2 Dois.mp3", "10 Dez.flac"])
        let url = try await source.url(for: items[1])
        #expect(url.lastPathComponent == "2 Dois.mp3")
        await #expect(throws: SourceError.self) { try await source.list("Não existe") }
    }
}
