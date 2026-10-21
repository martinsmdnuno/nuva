import Foundation

/// What MusicBrainz knows about a CD: the names a disc doesn't carry.
struct DiscInfo: Codable, Equatable, Sendable {
    let artist: String
    let album: String
    /// Track titles, in disc order.
    let titles: [String]
    /// MusicBrainz release, for the cover.
    let releaseID: String
}

/// Names and covers of audio CDs, by MusicBrainz disc ID. A CD has no folder or file names
/// to respect, so this is the second agreed exception to "no online lookups".
/// Answers are kept in Application Support, so a known disc works offline.
struct DiscLookup: Sendable {
    let root: URL
    var online: CoverArtArchive = .shared

    static let standard = DiscLookup(root: URL.applicationSupportDirectory
        .appendingPathComponent("NuVa/Discs", isDirectory: true))

    /// Longest wait for MusicBrainz when a disc goes in, so playback isn't held up.
    static let timeout: Duration = .seconds(8)

    /// Cached names, or MusicBrainz's answer; nil when the disc isn't known or the lookup fails.
    func info(for toc: DiscTOC) async -> DiscInfo? {
        let id = toc.musicBrainzID
        let file = root.appendingPathComponent("\(Self.safe(id)).json", isDirectory: false)
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(DiscInfo.self, from: data) {
            return cached
        }
        let online = self.online
        let found = await withTaskGroup(of: DiscInfo?.self) { group in
            group.addTask { try? await online.disc(toc) }
            group.addTask { try? await Task.sleep(for: Self.timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let found, let data = try? JSONEncoder().encode(found) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return found
    }

    /// The release's front cover, downloaded once and kept next to the names.
    func cover(for toc: DiscTOC, info: DiscInfo) async -> URL? {
        let file = root.appendingPathComponent("\(Self.safe(toc.musicBrainzID)).jpg", isDirectory: false)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let data = try? await online.releaseFront(info.releaseID) else { return nil }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) == nil ? nil : file
    }

    /// Disc IDs are URL-safe Base64; "." is the only character to keep out of a file name's start.
    private static func safe(_ id: String) -> String { "disc-\(id)" }
}

extension CoverArtArchive {
    private struct DiscResponse: Decodable {
        let releases: [Release]?
    }

    struct Release: Decodable, Sendable {
        struct Credit: Decodable, Sendable {
            let name: String
            let joinphrase: String?
        }
        struct Medium: Decodable, Sendable {
            struct Disc: Decodable, Sendable { let id: String }
            struct Track: Decodable, Sendable { let title: String }
            let discs: [Disc]?
            let tracks: [Track]?
        }
        let id: String
        let title: String
        let artistCredit: [Credit]?
        let media: [Medium]?

        enum CodingKeys: String, CodingKey {
            case id, title, media
            case artistCredit = "artist-credit"
        }

        var artist: String { (artistCredit ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined() }
    }

    /// Names of the release that has this disc (by disc ID, or by the TOC when the ID is new).
    func disc(_ toc: DiscTOC) async throws -> DiscInfo? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/discid/\(toc.musicBrainzID)")!
        components.queryItems = [
            URLQueryItem(name: "toc", value: toc.musicBrainzTOC),
            URLQueryItem(name: "cdstubs", value: "no"),
            URLQueryItem(name: "inc", value: "artist-credits recordings"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        guard let (data, response) = try await get(components.url!, accept: "application/json"),
              response.statusCode != 404 else { return nil }
        guard response.statusCode == 200 else { throw HTTPStatusError(code: response.statusCode) }
        let releases = try JSONDecoder().decode(DiscResponse.self, from: data).releases ?? []
        return Self.pick(releases, for: toc)
    }

    /// The medium with this exact disc ID wins; otherwise the first with the same number of tracks.
    static func pick(_ releases: [Release], for toc: DiscTOC) -> DiscInfo? {
        let count = toc.starts.count
        let candidates = releases.flatMap { release in (release.media ?? []).map { (release, $0) } }
        let exact = candidates.first { $0.1.discs?.contains { $0.id == toc.musicBrainzID } == true }
        guard let (release, medium) = exact ?? candidates.first(where: { $0.1.tracks?.count == count }),
              let tracks = medium.tracks, tracks.count == count else { return nil }
        return DiscInfo(artist: release.artist, album: release.title, titles: tracks.map(\.title), releaseID: release.id)
    }

    /// JPEG of the release's front cover (500 px), or nil if it has none.
    func releaseFront(_ release: String) async throws -> Data? {
        let url = URL(string: "https://coverartarchive.org/release/\(release)/front-500")!
        guard let (data, response) = try await get(url), response.statusCode != 404 else { return nil }
        guard response.statusCode == 200 else { throw HTTPStatusError(code: response.statusCode) }
        return response.mimeType?.hasPrefix("image/") == true ? data : nil
    }
}
