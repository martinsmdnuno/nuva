import Foundation
import Observation

/// Where the browser is: in the source list or in a folder of a source.
struct BrowserLocation: Hashable, Sendable {
    let sourceID: UUID
    let path: String
}

/// The tracks under a folder, and what couldn't be listed on the way.
struct FolderTracks: Sendable {
    var tracks: [Entry] = []
    /// Folders that failed to list (the folder itself or one below it).
    var unreadable = 0
    /// The first failure, for the message.
    var error: (any Error)?
}

/// Folder browser state.
@MainActor
@Observable
final class Browser {
    private(set) var location: BrowserLocation?
    /// The folder's entries, folders in `folderOrder`.
    private(set) var entries: [Entry] = []
    /// Names (as they are) or the newest music first; remembered (`folderOrder`).
    var folderOrder: FolderOrder {
        didSet {
            defaults.set(folderOrder.rawValue, forKey: "folderOrder")
            entries = entries.sorted(by: folderOrder)
        }
    }
    private(set) var errorMessage: String?
    /// Listing the folder (a slow server or network disk).
    private(set) var isLoading = false
    /// Summary per folder: "12 faixas", "2 pastas".
    private(set) var summaries: [Entry.ID: String] = [:]

    @ObservationIgnored private let sources: SourceStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadToken = 0

    init(sources: SourceStore, defaults: UserDefaults = .standard) {
        self.sources = sources
        self.defaults = defaults
        self.folderOrder = FolderOrder(rawValue: defaults.string(forKey: "folderOrder") ?? "") ?? .name
    }

    func toggleFolderOrder() {
        folderOrder = folderOrder == .recent ? .name : .recent
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
        loadToken += 1
        guard let location, let source = sources.source(location.sourceID) else {
            isLoading = false
            return
        }
        let token = loadToken
        isLoading = true
        Task {
            do {
                let items = try await source.list(location.path)
                guard token == loadToken else { return }
                entries = items.sorted(by: folderOrder)
            } catch {
                Log.shared.error(.source, "list-failed", error, detail: location.path)
                guard token == loadToken else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
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
        await collect(in: folder).tracks
    }

    /// The same tracks, with the folders that couldn't be listed counted instead of left out in silence.
    func collect(in folder: BrowserLocation) async -> FolderTracks {
        var found = FolderTracks()
        guard let source = sources.source(folder.sourceID) else {
            found.unreadable = 1
            found.error = SourceError.missingFolder((folder.path as NSString).lastPathComponent)
            return found
        }
        await Self.collect(source, folder.path, into: &found)
        return found
    }

    private nonisolated static func collect(_ source: any MusicSource, _ path: String, into found: inout FolderTracks) async {
        let items: [Entry]
        do {
            items = try await source.list(path)
        } catch {
            Log.shared.error(.source, "list-failed", error, detail: path)
            found.unreadable += 1
            if found.error == nil { found.error = error }
            return
        }
        found.tracks += items.filter { $0.kind == .track }
        for sub in items where sub.kind == .folder {
            await collect(source, sub.path, into: &found)
        }
    }
}
