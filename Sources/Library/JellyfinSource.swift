import CryptoKit
import Foundation

/// Source on a Jellyfin server. Browses the server's disk folders (each item's `Path`),
/// not Jellyfin's artists and albums. Plays the original file, without conversion.
actor JellyfinSource: MusicSource {
    nonisolated let id: UUID
    nonisolated let name: String
    nonisolated let kind = SourceKind.jellyfin
    nonisolated let server: URL
    nonisolated let username: String
    private let deviceID: String
    private let password: @Sendable () -> String?
    private let urlSession: URLSession
    /// Where the folders' images fetched from the server are kept (the app's caches, never the music).
    private let artworkCache: URL

    struct Session: Sendable {
        let token: String
        let userID: String
    }

    struct Item: Decodable, Sendable {
        let id: String
        let name: String?
        let isFolder: Bool?
        let path: String?
        let container: String?
        let runTimeTicks: Int64?
        let collectionType: String?
        var dateCreated: String? = nil
        var dateLastMediaAdded: String? = nil

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", isFolder = "IsFolder", path = "Path", container = "Container"
            case runTimeTicks = "RunTimeTicks", collectionType = "CollectionType"
            case dateCreated = "DateCreated", dateLastMediaAdded = "DateLastMediaAdded"
        }

        /// The newer of when Jellyfin found the folder and when it last found music in it.
        var added: Date? {
            [dateCreated, dateLastMediaAdded].compactMap { $0.flatMap(JellyfinSource.date) }.max()
        }

        /// Path with forward slashes (Windows servers use `\`).
        var unixPath: String? { path?.replacingOccurrences(of: "\\", with: "/") }
    }

    private struct Items: Decodable {
        let items: [Item]
        enum CodingKeys: String, CodingKey { case items = "Items" }
    }

    /// Known folder: item id and path on the server's disk (nil at the library root).
    private struct Node {
        let id: String
        let abs: String?
    }

    private var session: Session?
    /// A sign-in in progress, shared by everyone who needs a session meanwhile.
    private var signingIn: Task<Session, Error>?
    private var legacyRoutes = false
    private var rootLoaded = false
    /// With more than one music library, the root shows the libraries.
    private var libraries: [Item] = []
    private var nodes: [String: Node] = [:]
    private var tracks: [String: String] = [:]
    private var listed: Set<String> = []
    private var cache: [String: (items: [Item], at: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300

    init(
        id: UUID, name: String, server: URL, username: String, deviceID: String,
        password: @escaping @Sendable () -> String?, urlSession: URLSession = .shared,
        artworkCache: URL = URL.cachesDirectory.appendingPathComponent("NuVa/Jellyfin", isDirectory: true)
    ) {
        self.artworkCache = artworkCache.appendingPathComponent(id.uuidString, isDirectory: true)
        self.id = id
        self.name = name
        self.server = server
        self.username = username
        self.deviceID = deviceID
        self.password = password
        self.urlSession = urlSession
    }

    // MARK: MusicSource

    func list(_ path: String) async throws -> [Entry] {
        if !rootLoaded { try await loadRoot() }
        if path.isEmpty, !libraries.isEmpty {
            listed.insert("")
            return libraries.map { Entry(sourceID: id, path: $0.name ?? $0.id, name: $0.name ?? $0.id, kind: .folder) }
                .naturallySorted()
        }
        let (anchorRel, anchor) = try await anchor(for: path)
        let children = try await items(in: anchor.id)
        let placed = children.map { ($0, register($0, anchorRel: anchorRel, anchorAbs: anchor.abs)) }
        listed.insert(path)

        // Direct children of `path`; deeper items (an album with CD1/CD2) yield folders from the path.
        var result: [Entry] = []
        var folders: [String: Int] = [:]
        // A folder seen twice (itself and through a deeper item) keeps the newest date.
        func addFolder(_ path: String, _ name: String, _ added: Date?) {
            if let index = folders[path] {
                result[index].added = [result[index].added, added].compactMap { $0 }.max()
            } else {
                folders[path] = result.count
                result.append(Entry(sourceID: id, path: path, name: name, kind: .folder, added: added))
            }
        }
        let prefix = path.isEmpty ? "" : path + "/"
        for (item, rel) in placed where rel.hasPrefix(prefix) {
            let rest = rel.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                addFolder(prefix + rest[..<slash], String(rest[..<slash]), item.added)
            } else if item.isFolder == true {
                addFolder(rel, String(rest), item.added)
            } else if Playable.isPlayable(rel) {
                let duration = item.runTimeTicks.map { Double($0) / 10_000_000 }
                result.append(Entry(sourceID: id, path: rel, name: String(rest), kind: .track, duration: duration))
            }
        }
        return result.naturallySorted()
    }

    func url(for track: Entry) async throws -> URL {
        if tracks[track.path] == nil { _ = try await list(track.parentPath) }
        guard let itemID = tracks[track.path] else { throw SourceError.missingFolder(track.folderName) }
        let token = try await currentSession().token
        let ext = (track.name as NSString).pathExtension.lowercased()
        // static=true: the original file, no transcoding.
        return server.appending(path: "Audio/\(itemID)/stream.\(ext)").appending(queryItems: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token),
        ])
    }

    // MARK: Artwork

    /// One of a server item's images: its type ("Primary"), the file it was read from, its index.
    struct FolderImage: Decodable, Sendable {
        let type: String
        let path: String?
        let index: Int?

        enum CodingKeys: String, CodingKey { case type = "ImageType", path = "Path", index = "ImageIndex" }
    }

    /// The image whose file sits in `folder` itself (the server's path, `/` or `\`) and is named as
    /// artwork (cover.jpg, folder.png…). Never one Jellyfin took from the tags or downloaded.
    static func folderImage(among images: [FolderImage], in folder: String) -> FolderImage? {
        var dir = folder.replacingOccurrences(of: "\\", with: "/")
        while dir.hasSuffix("/") { dir.removeLast() }
        var byName: [String: FolderImage] = [:]
        for image in images {
            guard let path = image.path?.replacingOccurrences(of: "\\", with: "/"),
                  (path as NSString).deletingLastPathComponent == dir else { continue }
            byName[(path as NSString).lastPathComponent] = image
        }
        return Artwork.pick(from: Array(byName.keys)).flatMap { byName[$0] }
    }

    /// The image file the user put in the folder on the server, fetched into the app's caches.
    /// Offline, the copy fetched before is used; a folder that no longer has an image loses its copy.
    func artwork(inFolder path: String) async -> URL? {
        let hash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = artworkCache.appendingPathComponent(String(hash.prefix(32)) + ".img")
        let fm = FileManager.default
        do {
            guard let data = try await folderArtwork(path) else {
                try? fm.removeItem(at: file)
                return nil
            }
            try fm.createDirectory(at: artworkCache, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            Log.shared.error(.artwork, "jellyfin-folder-image-failed", error)
            return fm.fileExists(atPath: file.path) ? file : nil
        }
    }

    private func folderArtwork(_ path: String) async throws -> Data? {
        if !rootLoaded { try await loadRoot() }
        guard let (rel, node) = try? await anchor(for: path), rel == path, let abs = node.abs else { return nil }
        let listing = try await data("Items/\(node.id)/Images", [])
        guard let images = try? JSONDecoder().decode([FolderImage].self, from: listing),
              let image = Self.folderImage(among: images, in: abs) else { return nil }
        let index = image.index.map { "/\($0)" } ?? ""
        let bytes = try await data("Items/\(node.id)/Images/\(image.type)\(index)", [
            URLQueryItem(name: "maxWidth", value: "800"), URLQueryItem(name: "quality", value: "90"),
        ])
        return bytes.isEmpty ? nil : bytes
    }

    // MARK: Folder tree

    /// Relative path of an item: the part of `Path` below the anchor folder or, without one, the last name.
    static func relativePath(of item: Item, anchorRel: String, anchorAbs: String?) -> String {
        let leaf: String
        if let abs = anchorAbs, let path = item.unixPath, path.hasPrefix(abs + "/") {
            leaf = String(path.dropFirst(abs.count + 1))
        } else if let path = item.unixPath {
            leaf = (path as NSString).lastPathComponent
        } else {
            let name = item.name ?? item.id
            leaf = item.isFolder == true || item.container == nil ? name : "\(name).\(item.container!)"
        }
        return anchorRel.isEmpty ? leaf : "\(anchorRel)/\(leaf)"
    }

    private func register(_ item: Item, anchorRel: String, anchorAbs: String?) -> String {
        let rel = Self.relativePath(of: item, anchorRel: anchorRel, anchorAbs: anchorAbs)
        if item.isFolder == true {
            nodes[rel] = Node(id: item.id, abs: item.unixPath)
        } else {
            tracks[rel] = item.id
        }
        return rel
    }

    /// The closest known folder to `path`. After reopening the app the ids aren't in memory:
    /// lists each level from the root until they're found.
    private func anchor(for path: String) async throws -> (String, Node) {
        var prefix = ""
        for part in path.split(separator: "/").map(String.init) {
            let next = prefix.isEmpty ? part : "\(prefix)/\(part)"
            if nodes[next] == nil, !listed.contains(prefix) { _ = try await list(prefix) }
            prefix = next
        }
        var p = path
        while true {
            if let node = nodes[p] { return (p, node) }
            if p.isEmpty { throw SourceError.missingFolder((path as NSString).lastPathComponent) }
            p = (p as NSString).deletingLastPathComponent
        }
    }

    private func loadRoot() async throws {
        let views = try await userViews().filter { $0.collectionType == "music" }
        guard !views.isEmpty else { throw SourceError.noMusicLibrary }
        if views.count == 1 {
            nodes[""] = Node(id: views[0].id, abs: nil)
        } else {
            libraries = views
            for view in views { nodes[view.name ?? view.id] = Node(id: view.id, abs: nil) }
        }
        rootLoaded = true
    }

    // MARK: API

    private func userViews() async throws -> [Item] {
        let userID = try await currentSession().userID
        if !legacyRoutes {
            do {
                return try await get("UserViews", [URLQueryItem(name: "userId", value: userID)])
            } catch HTTPError.status(404) {
                legacyRoutes = true
            }
        }
        return try await get("Users/\(userID)/Views", [])
    }

    private func items(in parentID: String) async throws -> [Item] {
        if let hit = cache[parentID], Date().timeIntervalSince(hit.at) < Self.cacheTTL { return hit.items }
        let userID = try await currentSession().userID
        let query = [
            URLQueryItem(name: "parentId", value: parentID),
            URLQueryItem(name: "fields", value: "Path,DateCreated,DateLastMediaAdded"),
            URLQueryItem(name: "enableImages", value: "false"),
            URLQueryItem(name: "enableUserData", value: "false"),
        ]
        var result: [Item]
        if !legacyRoutes {
            do {
                result = try await get("Items", query + [URLQueryItem(name: "userId", value: userID)])
            } catch HTTPError.status(404) {
                legacyRoutes = true
                result = try await get("Users/\(userID)/Items", query)
            }
        } else {
            result = try await get("Users/\(userID)/Items", query)
        }
        cache[parentID] = (result, Date())
        return result
    }

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> [Item] {
        let data = try await data(path, query)
        guard let decoded = try? JSONDecoder().decode(Items.self, from: data) else { throw SourceError.unexpectedResponse }
        return decoded.items
    }

    /// A signed GET. A 401 signs in again once.
    private func data(_ path: String, _ query: [URLQueryItem], retry: Bool = true) async throws -> Data {
        let session = try await currentSession()
        var url = server.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.setValue(Self.authorization(deviceID: deviceID, token: session.token), forHTTPHeaderField: "Authorization")
        let (data, status) = try await Self.send(request, urlSession)
        if status == 401, retry {
            // Token revoked or expired: sign in again with the saved password.
            self.session = nil
            return try await self.data(path, query, retry: false)
        }
        guard (200..<300).contains(status) else { throw HTTPError.status(status) }
        return data
    }

    private func currentSession() async throws -> Session {
        if let session { return session }
        if let signingIn { return try await signingIn.value }
        guard let password = password() else { throw SourceError.loginFailed }
        let (server, username, deviceID, urlSession) = (server, username, deviceID, urlSession)
        let task = Task {
            try await Self.login(server: server, username: username, password: password, deviceID: deviceID, urlSession: urlSession)
        }
        signingIn = task
        defer { signingIn = nil }
        let fresh = try await task.value
        session = fresh
        return fresh
    }

    /// The stream URL carries the token, so a revoked token only shows up as a failed stream.
    func streamFailed() {
        session = nil
    }

    static func login(
        server: URL, username: String, password: String, deviceID: String, urlSession: URLSession = .shared
    ) async throws -> Session {
        struct Response: Decodable {
            struct User: Decodable { let Id: String }
            let AccessToken: String
            let User: User
        }
        var request = URLRequest(url: server.appending(path: "Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization(deviceID: deviceID, token: nil), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])
        let (data, status) = try await send(request, urlSession)
        if status == 401 || status == 403 { throw SourceError.loginFailed }
        guard (200..<300).contains(status) else { throw HTTPError.status(status) }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SourceError.unexpectedResponse
        }
        return Session(token: response.AccessToken, userID: response.User.Id)
    }

    /// Jellyfin's dates ("2025-03-14T09:26:53.1234567Z", seven decimals or none), to a Date.
    static func date(_ text: String) -> Date? {
        let whole = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let zoned = whole.hasSuffix("Z") || whole.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        return try? Date(zoned ? whole : whole + "Z", strategy: .iso8601)
    }

    private static func authorization(deviceID: String, token: String?) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        var value = #"MediaBrowser Client="NuVa", Device="Mac", DeviceId="\#(deviceID)", Version="\#(version)""#
        if let token { value += #", Token="\#(token)""# }
        return value
    }

    private static func send(_ request: URLRequest, _ urlSession: URLSession) async throws -> (Data, Int) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw SourceError.serverUnavailable
        }
    }

    enum HTTPError: LocalizedError {
        case status(Int)
        var errorDescription: String? {
            switch self { case .status(let code): String(localized: "O servidor respondeu \(code)") }
        }
    }
}
