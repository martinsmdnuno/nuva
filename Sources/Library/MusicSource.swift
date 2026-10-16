import Foundation

/// Uma pasta ou uma faixa dentro de uma fonte. O caminho é relativo à raiz da fonte.
struct Entry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case folder, track }

    let sourceID: UUID
    let path: String
    let name: String
    let kind: Kind

    var id: String { "\(sourceID.uuidString)/\(path)" }

    /// Extensão em maiúsculas, para o display ("FLAC").
    var format: String { (name as NSString).pathExtension.uppercased() }

    /// Nome do ficheiro sem extensão nem número inicial ("01 - ", "1. ", "01_").
    var title: String {
        let base = (name as NSString).deletingPathExtension
        let stripped = base.replacingOccurrences(
            of: #"^\d{1,3}(\s*[-–._)]\s*|\s+)"#, with: "", options: .regularExpression)
        return stripped.isEmpty ? base : stripped
    }

    /// Nome da pasta que contém a entrada.
    var folderName: String {
        let parent = (path as NSString).deletingLastPathComponent
        return (parent as NSString).lastPathComponent
    }

    /// Caminho da pasta que contém a entrada.
    var parentPath: String { (path as NSString).deletingLastPathComponent }
}

enum SourceKind: String, Codable, Sendable {
    case local, server

    var label: String { self == .local ? "Local" : "Servidor" }
    var symbol: String { self == .local ? "internaldrive" : "server.rack" }
}

/// Uma árvore de pastas de onde a app toca. O player não sabe de onde vem a música.
protocol MusicSource: Sendable {
    var id: UUID { get }
    var name: String { get }
    var kind: SourceKind { get }
    /// Pastas e faixas em `path` ("" é a raiz), pastas primeiro, ordem natural.
    func list(_ path: String) async throws -> [Entry]
    /// URL tocável da faixa: file:// ou https://.
    func url(for track: Entry) async throws -> URL
}

enum SourceError: LocalizedError {
    case missingFolder(String)
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .missingFolder(let name): "Pasta em falta: \(name)"
        case .serverUnavailable: "Servidor offline. Tentar de novo"
        }
    }
}

enum Playable {
    static let extensions: Set<String> = ["flac", "mp3", "m4a", "aac", "alac", "wav", "aiff"]

    static func isPlayable(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }
}

extension [Entry] {
    /// Pastas primeiro, depois faixas; dentro de cada grupo, ordem natural do nome.
    func naturallySorted() -> [Entry] {
        sorted { a, b in
            if a.kind != b.kind { return a.kind == .folder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
