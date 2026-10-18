import AppKit
import Foundation
import Observation

/// As fontes da app, lembradas entre arranques em UserDefaults.
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
    /// Fontes guardadas que não abriram (pasta apagada, disco desligado), por id.
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

    /// Abre o NSOpenPanel e junta a pasta escolhida como fonte Local.
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

    /// Entra no Jellyfin para validar os dados e junta-o como fonte. A palavra-passe fica no Keychain.
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

    /// Identifica este Mac no Jellyfin (aparece em Dispositivos no painel).
    private var deviceID: String {
        if let id = defaults.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceID")
        return id
    }

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
            case .server:
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
    /// URL tocável de uma faixa, pela fonte a que pertence.
    func resolve(_ entry: Entry) async throws -> URL {
        guard let source = source(entry.sourceID) else {
            throw SourceError.missingFolder(entry.folderName)
        }
        return try await source.url(for: entry)
    }
}
