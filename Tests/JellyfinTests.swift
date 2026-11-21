import Foundation
import Testing
@testable import NuVa

/// Fake Jellyfin server: responds by path and parentId.
final class FakeJellyfin: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let parent = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "parentId" }?.value
        Self.requests.append(url.path + (parent.map { "?\($0)" } ?? ""))
        let body: String
        switch (url.path, parent) {
        case ("/jf/Users/AuthenticateByName", _):
            body = #"{"AccessToken":"tok","User":{"Id":"u1"}}"#
        case ("/jf/UserViews", _):
            body = #"{"Items":[{"Id":"lib","Name":"Música","CollectionType":"music","IsFolder":true},{"Id":"mov","Name":"Filmes","CollectionType":"movies","IsFolder":true}]}"#
        case ("/jf/Items", "lib"):
            body = #"{"Items":[{"Id":"art","Name":"Artista X","IsFolder":true,"Path":"/music/Artist","DateCreated":"2024-01-02T03:04:05.1234567Z","DateLastMediaAdded":"2026-11-20T21:00:00.0000000Z"}]}"#
        case ("/jf/Items", "art"):
            body = #"{"Items":[{"Id":"alb","Name":"Nome das tags","IsFolder":true,"Path":"/music/Artist/2001 Álbum"}]}"#
        case ("/jf/Items", "alb"):
            body = #"{"Items":[{"Id":"t2","Name":"Dois","IsFolder":false,"Path":"/music/Artist/2001 Álbum/CD2/01 Um.flac","RunTimeTicks":1800000000},{"Id":"t1","Name":"Um","IsFolder":false,"Path":"/music/Artist/2001 Álbum/CD1/01 Um.flac","RunTimeTicks":2400000000},{"Id":"t3","Name":"Capa","IsFolder":false,"Path":"/music/Artist/2001 Álbum/notas.txt"}]}"#
        case ("/jf/Items/alb/Images", _):
            // Two images: one Jellyfin made from the tags (in its own metadata folder), one the user's file.
            body = #"[{"ImageType":"Backdrop","ImageIndex":0,"Path":"/config/metadata/library/ab/backdrop.jpg"},{"ImageType":"Primary","Path":"/music/Artist/2001 Álbum/Cover.JPG"}]"#
        case ("/jf/Items/alb/Images/Primary", _):
            body = "the cover's bytes"
        case ("/jf/Items/art/Images", _):
            body = #"[{"ImageType":"Primary","Path":"/config/metadata/artists/Artist/folder.jpg"}]"#
        default:
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct JellyfinTests {
    private let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func source() -> JellyfinSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeJellyfin.self]
        return JellyfinSource(
            id: UUID(), name: "Jellyfin", server: URL(string: "https://exemplo.pt/jf")!, username: "nuno",
            deviceID: "teste", password: { "segredo" }, urlSession: URLSession(configuration: config),
            artworkCache: cache)
    }

    @Test func browsesDiskFoldersNotTags() async throws {
        let jf = source()
        let root = try await jf.list("")
        #expect(root.map(\.name) == ["Artist"])
        // The newer of the two dates: when an album last landed in the artist's folder.
        #expect(root[0].added == JellyfinSource.date("2026-11-20T21:00:00Z"))
        #expect(try await jf.list("Artist").map(\.name) == ["2001 Álbum"])
        let album = try await jf.list("Artist/2001 Álbum")
        #expect(album.map(\.name) == ["CD1", "CD2"])
        let cd1 = try await jf.list("Artist/2001 Álbum/CD1")
        #expect(cd1.map(\.name) == ["01 Um.flac"])
        #expect(cd1[0].duration == 240)
        let url = try await jf.url(for: cd1[0])
        #expect(url.absoluteString == "https://exemplo.pt/jf/Audio/t1/stream.flac?static=true&api_key=tok")
    }

    @Test func findsTrackAfterRelaunch() async throws {
        // New source, no ids in memory: walks the tree from the path.
        let jf = source()
        let entry = Entry(sourceID: jf.id, path: "Artist/2001 Álbum/CD2/01 Um.flac", name: "01 Um.flac", kind: .track)
        let url = try await jf.url(for: entry)
        #expect(url.path == "/jf/Audio/t2/stream.flac")
    }

    /// Folders, not metadata: only the image file in the album's own folder, never Jellyfin's own.
    @Test func coverIsTheImageFileInTheAlbumsFolder() async throws {
        defer { try? FileManager.default.removeItem(at: cache) }
        let jf = source()
        let cover = try #require(await jf.artwork(inFolder: "Artist/2001 Álbum"))
        #expect(try String(contentsOf: cover, encoding: .utf8) == "the cover's bytes")
        // The artist's folder has only an image Jellyfin keeps elsewhere.
        #expect(await jf.artwork(inFolder: "Artist") == nil)

        let images = [
            JellyfinSource.FolderImage(type: "Primary", path: #"D:\Music\Tusk\front.png"#, index: nil),
            JellyfinSource.FolderImage(type: "Thumb", path: #"D:\Music\Tusk\cover.jpg"#, index: 1),
            JellyfinSource.FolderImage(type: "Logo", path: #"D:\Music\Tusk\CD1\cover.jpg"#, index: nil),
            JellyfinSource.FolderImage(type: "Art", path: nil, index: nil),
        ]
        #expect(JellyfinSource.folderImage(among: images, in: #"D:\Music\Tusk\"#)?.type == "Thumb")
        #expect(JellyfinSource.folderImage(among: images, in: "/music/Tusk") == nil)
    }

    @Test func readsJellyfinDates() {
        let expected = Date(timeIntervalSince1970: 1_731_582_413)  // 2024-11-14T11:06:53Z
        #expect(JellyfinSource.date("2024-11-14T11:06:53.1234567Z") == expected)
        #expect(JellyfinSource.date("2024-11-14T11:06:53Z") == expected)
        #expect(JellyfinSource.date("2024-11-14T11:06:53") == expected)
        #expect(JellyfinSource.date("2024-11-14T12:06:53.5+01:00") == expected)
        #expect(JellyfinSource.date("0001-01-01") == nil)
    }
}
