import Foundation
import os

/// Tracks the Finder handed to NuVa ("Open With", a drop on the Dock icon or the window) that are in
/// no source. macOS gives a sandboxed app the file itself and nothing around it, so such a track
/// plays alone, for this launch only: it is never saved and never shown among the sources.
/// The path is the file's own path on disk, so the display names its real folders.
final class OpenedFiles: MusicSource {
    let id = UUID()
    let name = "Finder"
    let kind = SourceKind.local
    private let files = OSAllocatedUnfairLock(initialState: [String: URL]())

    /// The track for a file, remembered so it can be played.
    func add(_ url: URL) -> Entry {
        let path = String(url.standardizedFileURL.path.drop { $0 == "/" })
        files.withLock { $0[path] = url }
        return Entry(sourceID: id, path: path, name: url.lastPathComponent, kind: .track)
    }

    /// The file behind a track, to show in the Finder.
    func file(_ track: Entry) -> URL? { files.withLock { $0[track.path] } }

    func list(_ path: String) async throws -> [Entry] { [] }

    func url(for track: Entry) async throws -> URL {
        guard let url = files.withLock({ $0[track.path] }), FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.missingFolder(track.folderName)
        }
        return url
    }
}
