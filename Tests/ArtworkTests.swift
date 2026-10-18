import AppKit
import MediaPlayer
import Testing
@testable import NuVa

struct ArtworkTests {
    @Test func picksByNameThenPreference() {
        #expect(Artwork.pick(from: ["01 Intro.flac", "Cover.JPG", "folder.png"]) == "Cover.JPG")
        #expect(Artwork.pick(from: ["back.jpg", "Folder.jpeg", "capa.jpg"]) == "Folder.jpeg")
        #expect(Artwork.pick(from: ["capa.png", "notas.txt"]) == "capa.png")
        // Other images, other formats and tag-like names don't count.
        #expect(Artwork.pick(from: ["back.jpg", "cover.webp", "cover.jpg.txt", "booklet.png"]) == nil)
    }

    @Test func localSourceFindsTheFolderImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let album = root.appendingPathComponent("Álbum")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        for name in ["01 Um.flac", "front.png", "scan.jpg"] {
            FileManager.default.createFile(atPath: album.appendingPathComponent(name).path, contents: Data())
        }
        let source = try LocalSource(id: UUID(), name: "Teste", bookmark: LocalSource.bookmark(for: root))
        #expect(await source.artwork(inFolder: "Álbum")?.lastPathComponent == "front.png")
        #expect(await source.artwork(inFolder: "") == nil)
        #expect(await source.artwork(inFolder: "Em falta") == nil)
    }

    @Test func downsampleCapsTheLongestSide() throws {
        let image = NSImage(size: NSSize(width: 2000, height: 1000), flipped: false) { rect in
            NSColor.orange.setFill(); rect.fill(); return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        let small = try #require(ArtworkStore.downsample(url))
        #expect(max(small.size.width, small.size.height) == CGFloat(ArtworkStore.maxPixels))
        #expect(ArtworkStore.downsample(URL(fileURLWithPath: "/nope.jpg")) == nil)
    }
}

@MainActor
struct NowPlayingArtworkTests {
    /// 1.1 crashed here: MediaPlayer asks for the image on its own queue, and the closure was main-actor isolated.
    @Test func artworkImageCanBeRequestedOffTheMainThread() async {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let artwork = NowPlaying.artwork(for: image)
        let size = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: artwork.image(at: CGSize(width: 10, height: 10))?.size)
            }
        }
        #expect(size == CGSize(width: 10, height: 10))
    }
}
