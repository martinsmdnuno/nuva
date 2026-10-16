import Foundation
import Testing
@testable import NuVa

/// Servidor Jellyfin falso: responde por caminho e parentId.
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
            body = #"{"Items":[{"Id":"art","Name":"Artista X","IsFolder":true,"Path":"/music/Artist"}]}"#
        case ("/jf/Items", "art"):
            body = #"{"Items":[{"Id":"alb","Name":"Nome das tags","IsFolder":true,"Path":"/music/Artist/2001 Álbum"}]}"#
        case ("/jf/Items", "alb"):
            body = #"{"Items":[{"Id":"t2","Name":"Dois","IsFolder":false,"Path":"/music/Artist/2001 Álbum/CD2/01 Um.flac","RunTimeTicks":1800000000},{"Id":"t1","Name":"Um","IsFolder":false,"Path":"/music/Artist/2001 Álbum/CD1/01 Um.flac","RunTimeTicks":2400000000},{"Id":"t3","Name":"Capa","IsFolder":false,"Path":"/music/Artist/2001 Álbum/notas.txt"}]}"#
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
    private func source() -> JellyfinSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeJellyfin.self]
        return JellyfinSource(
            id: UUID(), name: "Jellyfin", server: URL(string: "https://exemplo.pt/jf")!, username: "nuno",
            deviceID: "teste", password: { "segredo" }, urlSession: URLSession(configuration: config))
    }

    @Test func browsesDiskFoldersNotTags() async throws {
        let jf = source()
        #expect(try await jf.list("").map(\.name) == ["Artist"])
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
        // Fonte nova, sem ids em memória: percorre a árvore a partir do caminho.
        let jf = source()
        let entry = Entry(sourceID: jf.id, path: "Artist/2001 Álbum/CD2/01 Um.flac", name: "01 Um.flac", kind: .track)
        let url = try await jf.url(for: entry)
        #expect(url.path == "/jf/Audio/t2/stream.flac")
    }
}
