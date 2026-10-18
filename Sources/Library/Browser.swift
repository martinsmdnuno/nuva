import Foundation
import Observation

/// Where the browser is: in the source list or in a folder of a source.
struct BrowserLocation: Hashable, Sendable {
    let sourceID: UUID
    let path: String
}

/// Folder browser state.
@MainActor
@Observable
final class Browser {
    private(set) var location: BrowserLocation?
    private(set) var entries: [Entry] = []
    private(set) var errorMessage: String?
    /// Summary per folder: "12 faixas", "2 pastas".
    private(set) var summaries: [Entry.ID: String] = [:]

    @ObservationIgnored private let sources: SourceStore
    @ObservationIgnored private var loadToken = 0

    init(sources: SourceStore) {
        self.sources = sources
    }

    var source: (any MusicSource)? { location.flatMap { sources.source($0.sourceID) } }

    /// Name of the current location: folder, source, or "Fontes".
    var title: String {
        guard let location else { return String(localized: "Fontes") }
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

    /// Enter a folder.
    func enter(_ folder: Entry) {
        open(BrowserLocation(sourceID: folder.sourceID, path: folder.path))
    }

    /// Go up one level; from a source's root, back to the source list.
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
            if tracks > 0 { String(localized: "\(tracks) faixas") }
            else if folders > 0 { String(localized: "\(folders) pastas") }
            else { String(localized: "vazia") }
    }

    /// Tracks in a folder and its subfolders, in natural order (CD 01 before CD 02).
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
