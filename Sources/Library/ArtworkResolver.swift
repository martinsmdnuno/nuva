import CryptoKit
import Foundation

/// Where an album's artwork came from.
enum ArtworkOrigin: Sendable {
    /// An image file in the folder. Always wins; the user's own file is never "wrong".
    case folder
    /// Picked by the user for this folder (uploaded, or found by searching again).
    case user
    /// Found online from the folder names (MusicBrainz + Cover Art Archive).
    case online
}

struct ResolvedArtwork: Sendable {
    let url: URL
    let origin: ArtworkOrigin
}

/// Artwork files kept by NuVa in Application Support, never in the user's folders.
/// `online/` is shared by artist and album; `user/` is per folder, and a `.none` file means "no artwork".
struct ArtworkCache: Sendable {
    let root: URL
    /// How long a failed online lookup is remembered before trying again.
    static let missLifetime: TimeInterval = 14 * 24 * 3600

    static let standard = ArtworkCache(root: URL.applicationSupportDirectory
        .appendingPathComponent("NuVa/Artwork", isDirectory: true))

    enum Lookup: Equatable { case image(URL), none, unknown }

    func online(_ query: AlbumQuery) -> Lookup {
        lookup(dir: "online", key: query.key, missExpires: true)
    }

    func user(folder: String) -> Lookup {
        lookup(dir: "user", key: folder, missExpires: false)
    }

    @discardableResult
    func saveOnline(_ data: Data?, for query: AlbumQuery) -> URL? { save(data, dir: "online", key: query.key) }

    /// `nil` data records "no artwork" for this folder.
    @discardableResult
    func saveUser(_ data: Data?, folder: String) -> URL? { save(data, dir: "user", key: folder) }

    private func lookup(dir: String, key: String, missExpires: Bool) -> Lookup {
        let base = file(dir, key)
        let fm = FileManager.default
        if fm.fileExists(atPath: base.appendingPathExtension("jpg").path) { return .image(base.appendingPathExtension("jpg")) }
        let miss = base.appendingPathExtension("none")
        guard let date = (try? fm.attributesOfItem(atPath: miss.path))?[.modificationDate] as? Date else { return .unknown }
        return missExpires && Date().timeIntervalSince(date) > Self.missLifetime ? .unknown : .none
    }

    private func save(_ data: Data?, dir: String, key: String) -> URL? {
        let base = file(dir, key)
        let fm = FileManager.default
        try? fm.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        let jpg = base.appendingPathExtension("jpg"), miss = base.appendingPathExtension("none")
        try? fm.removeItem(at: jpg)
        try? fm.removeItem(at: miss)
        if let data {
            try? data.write(to: jpg, options: .atomic)
            return jpg
        }
        try? Data().write(to: miss)
        return nil
    }

    private func file(_ dir: String, _ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(dir, isDirectory: true).appendingPathComponent(String(hash.prefix(32)))
    }
}

/// Finds a folder's artwork: the folder's image, then the user's choice, then online by the folder names.
@MainActor
struct ArtworkResolver {
    let sources: SourceStore
    var cache = ArtworkCache.standard
    var online: CoverArtArchive = .shared

    /// Key of the folder that holds `entry` (disc folders count as their album).
    static func folderKey(_ entry: Entry) -> String {
        var folder = entry.parentPath
        while AlbumGuess.isDiscFolder((folder as NSString).lastPathComponent) {
            folder = (folder as NSString).deletingLastPathComponent
        }
        return "\(entry.sourceID.uuidString)/\(folder)"
    }

    /// Artist and album guessed from the folders holding `entry`.
    func query(for entry: Entry) -> AlbumQuery? {
        AlbumGuess.from(path: entry.parentPath, root: sources.source(entry.sourceID)?.rootFolderName)
    }

    func resolve(_ entry: Entry) async -> ResolvedArtwork? {
        if let url = await sources.artwork(for: entry) { return ResolvedArtwork(url: url, origin: .folder) }
        switch cache.user(folder: Self.folderKey(entry)) {
        case .image(let url): return ResolvedArtwork(url: url, origin: .user)
        case .none: return nil
        case .unknown: break
        }
        guard let query = query(for: entry) else { return nil }
        switch cache.online(query) {
        case .image(let url): return ResolvedArtwork(url: url, origin: .online)
        case .none: return nil
        case .unknown: break
        }
        do {
            let data = try await online.cover(for: query)
            return cache.saveOnline(data, for: query).map { ResolvedArtwork(url: $0, origin: .online) }
        } catch {
            // Offline or server error: try again next launch, don't record a miss.
            return nil
        }
    }
}
