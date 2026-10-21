import CryptoKit
import Darwin
import Foundation

/// An audio CD in the drive. macOS mounts it (cddafs) as a volume with one
/// "N Audio Track.aiff" per track. The root holds one folder for the disc, named
/// "Artist – Album" when MusicBrainz knows it, otherwise the volume's name.
/// Lives only while the disc is in the drive; never saved.
final class DiscSource: MusicSource {
    let id: UUID
    let kind = SourceKind.cd
    let volume: URL
    let toc: DiscTOC?
    let info: DiscInfo?
    /// The disc's one folder, also the source's name.
    let folder: String
    private let lookup: DiscLookup

    init(volume: URL, toc: DiscTOC?, info: DiscInfo?, lookup: DiscLookup = .standard) {
        self.volume = volume
        self.toc = toc
        self.info = info
        self.lookup = lookup
        // The same disc gets the same id every time, so its artwork choice and durations stick.
        self.id = Self.stableID(toc?.musicBrainzID ?? volume.path)
        let name = info.map { "\($0.artist) – \($0.album)" } ?? volume.lastPathComponent
        // A "/" would split the path (AC/DC).
        self.folder = name.replacingOccurrences(of: "/", with: "∕")
    }

    var name: String { folder }

    /// Whether the volume at `url` is an audio CD.
    static func isAudioCD(_ url: URL) -> Bool {
        var stats = statfs()
        guard statfs(url.path, &stats) == 0 else { return false }
        let type = withUnsafeBytes(of: stats.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return type == "cddafs"
    }

    func list(_ path: String) async throws -> [Entry] {
        if path.isEmpty { return [Entry(sourceID: id, path: folder, name: folder, kind: .folder)] }
        guard path == folder, let files = try? FileManager.default.contentsOfDirectory(atPath: volume.path) else {
            throw SourceError.missingFolder(folder)
        }
        return files.filter { !$0.hasPrefix(".") && Playable.isPlayable($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map(entry)
    }

    /// The file keeps its path; the name is the MusicBrainz title, numbered like a file ("03 Title.aiff").
    private func entry(_ file: String) -> Entry {
        let number = Int(file.prefix { $0.isNumber })
        var name = file
        if let number, let info, let toc, info.titles.indices.contains(number - toc.firstTrack) {
            let title = info.titles[number - toc.firstTrack]
            name = String(format: "%02d ", number) + title + "." + (file as NSString).pathExtension
        }
        return Entry(
            sourceID: id, path: "\(folder)/\(file)", name: name, kind: .track,
            duration: number.flatMap { toc?.duration(of: $0) })
    }

    func url(for track: Entry) async throws -> URL {
        let url = volume.appendingPathComponent((track.path as NSString).lastPathComponent, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SourceError.missingFolder(folder) }
        return url
    }

    /// The release's cover from the Cover Art Archive (only asked for while Show Artwork is on).
    func artwork(inFolder path: String) async -> URL? {
        guard path == folder, let toc, let info else { return nil }
        return await lookup.cover(for: toc, info: info)
    }

    private static func stableID(_ key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("disc/\(key)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
