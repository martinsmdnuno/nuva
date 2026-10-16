import Foundation
import Observation

/// Onde o navegador está: na lista de fontes ou numa pasta de uma fonte.
struct BrowserLocation: Hashable, Sendable {
    let sourceID: UUID
    let path: String
}

/// Estado do navegador de pastas.
@MainActor
@Observable
final class Browser {
    private(set) var location: BrowserLocation?
    private(set) var entries: [Entry] = []
    private(set) var errorMessage: String?
    /// Resumo por pasta: "12 faixas", "2 pastas".
    private(set) var summaries: [Entry.ID: String] = [:]

    @ObservationIgnored private let sources: SourceStore
    @ObservationIgnored private var loadToken = 0

    init(sources: SourceStore) {
        self.sources = sources
    }

    var source: (any MusicSource)? { location.flatMap { sources.source($0.sourceID) } }

    /// Nome do sítio atual: pasta, fonte, ou "Fontes".
    var title: String {
        guard let location else { return "Fontes" }
        if location.path.isEmpty { return source?.name ?? "" }
        return (location.path as NSString).lastPathComponent
    }

    func open(_ location: BrowserLocation?) {
        self.location = location
        entries = []
        errorMessage = nil
        guard let location, let source = sources.source(location.sourceID) else { return }
        loadToken += 1
        let token = loadToken
        Task {
            do {
                let items = try await source.list(location.path)
                guard token == loadToken else { return }
                entries = items
            } catch {
                guard token == loadToken else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func reload() { open(location) }

    /// Entrar numa pasta.
    func enter(_ folder: Entry) {
        open(BrowserLocation(sourceID: folder.sourceID, path: folder.path))
    }

    /// Subir um nível; da raiz de uma fonte volta à lista de fontes.
    func up() {
        guard let location else { return }
        if location.path.isEmpty {
            open(nil)
        } else {
            open(BrowserLocation(sourceID: location.sourceID, path: (location.path as NSString).deletingLastPathComponent))
        }
    }

    func loadSummary(_ folder: Entry) async {
        guard summaries[folder.id] == nil, let source = sources.source(folder.sourceID),
              let items = try? await source.list(folder.path) else { return }
        let tracks = items.count { $0.kind == .track }
        let folders = items.count - tracks
        summaries[folder.id] =
            if tracks > 0 { tracks == 1 ? "1 faixa" : "\(tracks) faixas" }
            else if folders > 0 { folders == 1 ? "1 pasta" : "\(folders) pastas" }
            else { "vazia" }
    }

    /// Faixas de uma pasta e das subpastas, por ordem natural (CD 01 antes de CD 02).
    func tracks(in folder: BrowserLocation) async -> [Entry] {
        guard let source = sources.source(folder.sourceID) else { return [] }
        return await Self.collect(source, folder.path)
    }

    private nonisolated static func collect(_ source: any MusicSource, _ path: String) async -> [Entry] {
        guard let items = try? await source.list(path) else { return [] }
        var result = items.filter { $0.kind == .track }
        for sub in items where sub.kind == .folder {
            result += await collect(source, sub.path)
        }
        return result
    }
}
