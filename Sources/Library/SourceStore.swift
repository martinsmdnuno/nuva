import AppKit
import Foundation
import Observation

/// The app's sources, remembered across launches in UserDefaults.
@MainActor
@Observable
final class SourceStore {
    private struct Record: Codable {
        let id: UUID
        var name: String
        let kind: SourceKind
        var bookmark: Data?
        var server: URL?
        var username: String?
    }

    private(set) var sources: [any MusicSource] = []
    /// Saved sources that failed to open (folder deleted, disk disconnected), by id.
    private(set) var failed: [UUID: String] = [:]

    private var records: [Record] = []
    private let defaults: UserDefaults
    private static let key = "sources"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func source(_ id: UUID) -> (any MusicSource)? {
        sources.first { $0.id == id }
    }

    /// Opens the NSOpenPanel and adds the chosen folder as a Local source.
    @discardableResult
    func addLocal() -> (any MusicSource)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Adicionar fonte")
        panel.message = String(localized: "Escolher a pasta da música")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return addLocal(url)
    }

    @discardableResult
    func addLocal(_ url: URL) -> (any MusicSource)? {
        if let existing = sources.compactMap({ $0 as? LocalSource }).first(where: { $0.root == url }) {
            return existing
        }
        guard let bookmark = try? LocalSource.bookmark(for: url) else { return nil }
        let record = Record(id: UUID(), name: url.lastPathComponent, kind: .local, bookmark: bookmark)
        guard let source = try? LocalSource(id: record.id, name: record.name, bookmark: bookmark) else {
            return nil
        }
        records.append(record)
        sources.append(source)
        save()
        return source
    }

    /// Signs in to Jellyfin to validate the details and adds it as a source. The password goes in the Keychain.
    func addJellyfin(server: URL, username: String, password: String) async throws -> any MusicSource {
        _ = try await JellyfinSource.login(server: server, username: username, password: password, deviceID: deviceID)
        let record = Record(
            id: UUID(), name: "Jellyfin · \(server.host() ?? server.absoluteString)", kind: .jellyfin,
            server: server, username: username)
        Keychain.setPassword(password, for: record.id.uuidString)
        let source = jellyfin(record, server: server, username: username)
        records.append(record)
        sources.append(source)
        save()
        return source
    }

    private func jellyfin(_ record: Record, server: URL, username: String) -> JellyfinSource {
        let account = record.id.uuidString
        return JellyfinSource(
            id: record.id, name: record.name, server: server, username: username, deviceID: deviceID,
            password: { Keychain.password(for: account) })
    }

    /// Identifies this Mac to Jellyfin (shown under Devices in the dashboard).
    private var deviceID: String {
        if let id = defaults.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceID")
        return id
    }

    /// Adds a CD while it is in the drive. Not saved: it goes away with the disc.
    func addDisc(_ disc: DiscSource) {
        guard source(disc.id) == nil else { return }
        sources.append(disc)
    }

    /// The CDs in the drive.
    var discs: [DiscSource] { sources.compactMap { $0 as? DiscSource } }

    func remove(_ id: UUID) {
        if records.first(where: { $0.id == id })?.kind == .jellyfin {
            Keychain.deletePassword(for: id.uuidString)
        }
        records.removeAll { $0.id == id }
        sources.removeAll { $0.id == id }
        failed[id] = nil
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([Record].self, from: data) else { return }
        records = saved
        var changed = false
        for (i, record) in records.enumerated() {
            switch record.kind {
            case .local:
                guard let bookmark = record.bookmark else { continue }
                do {
                    let source = try LocalSource(id: record.id, name: record.name, bookmark: bookmark)
                    if let fresh = source.refreshedBookmark {
                        records[i].bookmark = fresh
                        changed = true
                    }
                    sources.append(source)
                } catch {
                    failed[record.id] = SourceError.missingFolder(record.name).localizedDescription
                }
            case .jellyfin:
                guard let server = record.server, let username = record.username else { continue }
                sources.append(jellyfin(record, server: server, username: username))
            case .server, .cd:
                break
            }
        }
        if changed { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension SourceStore {
    /// Playable URL of a track, via the source it belongs to.
    func resolve(_ entry: Entry) async throws -> URL {
        guard let source = source(entry.sourceID) else {
            throw SourceError.missingFolder(entry.folderName)
        }
        return try await source.url(for: entry)
    }

    /// The image file in the folder that holds `entry`, if its source has one.
    /// A disc folder ("CD 01") also looks in the album folder above it.
    func artwork(for entry: Entry) async -> URL? {
        guard let source = source(entry.sourceID) else { return nil }
        var folder = entry.parentPath
        while true {
            if let url = await source.artwork(inFolder: folder) { return url }
            guard AlbumGuess.isDiscFolder((folder as NSString).lastPathComponent) else { return nil }
            folder = (folder as NSString).deletingLastPathComponent
        }
    }
}
