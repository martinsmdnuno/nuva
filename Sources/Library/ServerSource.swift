import Foundation

/// Fonte num servidor HTTP. Fase 2: por agora só o stub.
final class ServerSource: MusicSource {
    let id: UUID
    let name: String
    let kind = SourceKind.server
    let baseURL: URL

    init(id: UUID = UUID(), name: String, baseURL: URL) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }

    func list(_ path: String) async throws -> [Entry] {
        throw SourceError.serverUnavailable
    }

    func url(for track: Entry) async throws -> URL {
        throw SourceError.serverUnavailable
    }
}
