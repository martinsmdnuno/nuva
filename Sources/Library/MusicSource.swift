import Foundation

/// A folder or a track inside a source. The path is relative to the source root.
struct Entry: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case folder, track }

    let sourceID: UUID
    let path: String
    let name: String
    let kind: Kind
    /// Duration in seconds when the source already knows it (Jellyfin); nil for the Local source.
    var duration: Double? = nil

    var id: String { "\(sourceID.uuidString)/\(path)" }

    /// Uppercase extension, for the display ("FLAC").
    var format: String { (name as NSString).pathExtension.uppercased() }

    /// Name for lists: the file name without extension (the format is on the display), the folder name as is.
    var listName: String { kind == .track ? (name as NSString).deletingPathExtension : name }

    /// File name without extension or leading number ("01 - ", "1. ", "01_").
    var title: String {
        let base = (name as NSString).deletingPathExtension
        let stripped = base.replacingOccurrences(
            of: #"^\d{1,3}(\s*[-–._)]\s*|\s+)"#, with: "", options: .regularExpression)
        return stripped.isEmpty ? base : stripped
    }

    /// Name of the folder containing the entry.
    var folderName: String {
        let parent = (path as NSString).deletingLastPathComponent
        return (parent as NSString).lastPathComponent
    }

    /// Path of the folder containing the entry.
    var parentPath: String { (path as NSString).deletingLastPathComponent }
}

enum SourceKind: String, Codable, Sendable {
    case local, server, jellyfin

    var label: String {
        switch self {
        case .local: String(localized: "Local")
        case .server: String(localized: "Servidor")
        case .jellyfin: "Jellyfin"
        }
    }

    var symbol: String { self == .local ? "internaldrive" : "server.rack" }
}

/// A folder tree the app plays from. The player doesn't know where the music comes from.
protocol MusicSource: Sendable {
    var id: UUID { get }
    var name: String { get }
    var kind: SourceKind { get }
    /// Folders and tracks in `path` ("" is the root), folders first, natural order.
    func list(_ path: String) async throws -> [Entry]
    /// Playable URL of the track: file:// or https://.
    func url(for track: Entry) async throws -> URL
    /// An image file the user put in the folder (cover.jpg, folder.png…), or nil.
    /// Never from tags: folders, not metadata.
    func artwork(inFolder path: String) async -> URL?
}

extension MusicSource {
    func artwork(inFolder path: String) async -> URL? { nil }
}

enum Artwork {
    /// File names that count as the folder's artwork, in order of preference ("capa" is Portuguese).
    static let names = ["cover", "folder", "front", "album", "capa"]
    static let extensions: Set<String> = ["jpg", "jpeg", "png"]

    /// The artwork among a folder's file names, or nil. Case-insensitive.
    static func pick(from fileNames: [String]) -> String? {
        let candidates = fileNames.filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
        for name in names {
            if let match = candidates
                .filter({ ($0 as NSString).deletingPathExtension.lowercased() == name })
                .sorted()
                .first {
                return match
            }
        }
        return nil
    }
}

enum SourceError: LocalizedError {
    case missingFolder(String)
    case serverUnavailable
    case loginFailed
    case noMusicLibrary
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .missingFolder(let name): String(localized: "Pasta em falta: \(name)")
        case .serverUnavailable: String(localized: "Servidor offline. Tentar de novo")
        case .loginFailed: String(localized: "Utilizador ou palavra-passe errados")
        case .noMusicLibrary: String(localized: "Sem biblioteca de música neste utilizador")
        case .unexpectedResponse: String(localized: "Resposta inesperada. Confirmar o endereço do servidor")
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
    /// Folders first, then tracks; within each group, natural name order.
    func naturallySorted() -> [Entry] {
        sorted { a, b in
            if a.kind != b.kind { return a.kind == .folder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
