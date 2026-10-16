import Foundation

/// Fonte numa pasta do Mac (incluindo partilhas SMB montadas).
/// O acesso fica guardado num security-scoped bookmark.
final class LocalSource: MusicSource {
    let id: UUID
    let name: String
    let kind = SourceKind.local
    let root: URL
    private let accessing: Bool

    /// Resolve o bookmark e começa o acesso à pasta. Devolve também o bookmark
    /// renovado se o original estava desatualizado.
    init(id: UUID, name: String, bookmark: Data) throws {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale)
        self.id = id
        self.name = name
        self.root = url
        self.accessing = url.startAccessingSecurityScopedResource()
        self.refreshedBookmark = stale ? try? Self.bookmark(for: url) : nil
    }

    /// Bookmark novo quando o guardado estava desatualizado; nil se não mudou.
    let refreshedBookmark: Data?

    deinit {
        if accessing { root.stopAccessingSecurityScopedResource() }
    }

    static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func list(_ path: String) async throws -> [Entry] {
        let dir = path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let items: [URL]
        do {
            items = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            throw SourceError.missingFolder(path.isEmpty ? name : (path as NSString).lastPathComponent)
        }
        let entries = items.compactMap { url -> Entry? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let fileName = url.lastPathComponent
            let rel = path.isEmpty ? fileName : "\(path)/\(fileName)"
            if isDir { return Entry(sourceID: id, path: rel, name: fileName, kind: .folder) }
            guard Playable.isPlayable(fileName) else { return nil }
            return Entry(sourceID: id, path: rel, name: fileName, kind: .track)
        }
        return entries.naturallySorted()
    }

    func url(for track: Entry) async throws -> URL {
        let url = root.appendingPathComponent(track.path, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.missingFolder(track.folderName)
        }
        return url
    }
}
