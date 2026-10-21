import Foundation

/// Album covers from MusicBrainz (finds the album) and the Cover Art Archive (serves the image).
/// Open data, no key. Only confident matches count: a wrong cover is worse than none.
actor CoverArtArchive {
    static let shared = CoverArtArchive()

    /// MusicBrainz asks for an identifying User-Agent and at most one request per second.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        return "NuVa/\(version) ( https://github.com/martinsmdnuno/nuva )"
    }()

    private let session: URLSession
    private var lastRequest = Date.distantPast

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct ReleaseGroup: Decodable, Sendable {
        struct Credit: Decodable, Sendable { let name: String }
        let id: String
        let score: Int
        let title: String
        let artistCredit: [Credit]?

        enum CodingKeys: String, CodingKey {
            case id, score, title
            case artistCredit = "artist-credit"
        }

        var artist: String { (artistCredit ?? []).map(\.name).joined(separator: " ") }
    }

    /// Rate limited, server down…: an error, so a miss isn't remembered.
    struct HTTPStatusError: Error { let code: Int }

    private struct SearchResponse: Decodable {
        let releaseGroups: [ReleaseGroup]
        enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
    }

    /// JPEG data of the front cover (500 px), or nil when the album isn't found with confidence or has no cover.
    func cover(for query: AlbumQuery) async throws -> Data? {
        for group in try await search(query) where Self.matches(group, query) {
            if let data = try await front(of: group.id) { return data }
        }
        return nil
    }

    func search(_ query: AlbumQuery) async throws -> [ReleaseGroup] {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")!
        let lucene = "releasegroup:\"\(Self.escape(query.album))\" AND artist:\"\(Self.escape(query.artist))\""
        components.queryItems = [
            URLQueryItem(name: "query", value: lucene),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let (data, response) = try await get(components.url!, accept: "application/json") else { return [] }
        // Rate limited or down: an error, so the miss isn't remembered.
        guard response.statusCode == 200 else { throw HTTPStatusError(code: response.statusCode) }
        return try JSONDecoder().decode(SearchResponse.self, from: data).releaseGroups
    }

    private func front(of releaseGroup: String) async throws -> Data? {
        let url = URL(string: "https://coverartarchive.org/release-group/\(releaseGroup)/front-500")!
        guard let (data, response) = try await get(url), response.statusCode != 404 else { return nil }
        guard response.statusCode == 200 else { throw HTTPStatusError(code: response.statusCode) }
        return response.mimeType?.hasPrefix("image/") == true ? data : nil
    }

    /// A confident match: high MusicBrainz score, same artist and same album title once normalised.
    static func matches(_ group: ReleaseGroup, _ query: AlbumQuery) -> Bool {
        guard group.score >= 90 else { return false }
        let artist = AlbumGuess.normalize(query.artist), album = AlbumGuess.normalize(query.album)
        let foundArtist = AlbumGuess.normalize(group.artist), foundAlbum = AlbumGuess.normalize(group.title)
        let sameArtist = foundArtist == artist || foundArtist.hasPrefix(artist + " ") || artist.hasPrefix(foundArtist + " ")
        let sameAlbum = foundAlbum == album || AlbumGuess.normalize(AlbumGuess.clean(group.title)) == album
        return sameArtist && sameAlbum
    }

    /// Lucene special characters inside a quoted phrase.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func get(_ url: URL, accept: String? = nil) async throws -> (Data, HTTPURLResponse)? {
        // At most one request per second (MusicBrainz rate limit; applied to both hosts for simplicity).
        let wait = 1.1 - Date().timeIntervalSince(lastRequest)
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
        lastRequest = Date()
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        var (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 503 {
            // MusicBrainz is throttling: one more try after a pause.
            try await Task.sleep(for: .seconds(2))
            lastRequest = Date()
            (data, response) = try await session.data(for: request)
        }
        return (response as? HTTPURLResponse).map { (data, $0) }
    }
}
