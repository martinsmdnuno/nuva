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
        panel.prompt = "Adicionar fonte"
        panel.message = "Escolher a pasta da música"
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

    func remove(_ id: UUID) {
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
