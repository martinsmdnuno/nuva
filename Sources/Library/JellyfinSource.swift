import Foundation

/// Fonte num servidor Jellyfin. Navega pelas pastas do disco do servidor (o `Path` de cada item),
/// não pelos artistas e álbuns do Jellyfin. Toca o ficheiro original, sem conversão.
actor JellyfinSource: MusicSource {
    nonisolated let id: UUID
    nonisolated let name: String
    nonisolated let kind = SourceKind.jellyfin
    nonisolated let server: URL
    nonisolated let username: String
    private let deviceID: String
    private let password: @Sendable () -> String?
    private let urlSession: URLSession

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

        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", isFolder = "IsFolder", path = "Path", container = "Container"
            case runTimeTicks = "RunTimeTicks", collectionType = "CollectionType"
        }

        /// Caminho com barras normais (servidores Windows usam `\`).
        var unixPath: String? { path?.replacingOccurrences(of: "\\", with: "/") }
    }

    private struct Items: Decodable {
        let items: [Item]
        enum CodingKeys: String, CodingKey { case items = "Items" }
    }

    /// Pasta conhecida: id do item e caminho no disco do servidor (nil na raiz da biblioteca).
    private struct Node {
        let id: String
        let abs: String?
    }

    private var session: Session?
    private var legacyRoutes = false
    private var rootLoaded = false
    /// Com mais de uma biblioteca de música, a raiz mostra as bibliotecas.
    private var libraries: [Item] = []
    private var nodes: [String: Node] = [:]
    private var tracks: [String: String] = [:]
    private var listed: Set<String> = []
    private var cache: [String: (items: [Item], at: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300

    init(
        id: UUID, name: String, server: URL, username: String, deviceID: String,
        password: @escaping @Sendable () -> String?, urlSession: URLSession = .shared
    ) {
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

        // Filhos diretos de `path`; itens mais fundos (um álbum com CD1/CD2) dão pastas a partir do caminho.
        var result: [Entry] = []
        var seen: Set<String> = []
        let prefix = path.isEmpty ? "" : path + "/"
        for (item, rel) in placed where rel.hasPrefix(prefix) {
            let rest = rel.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                let sub = prefix + rest[..<slash]
                if seen.insert(sub).inserted {
                    result.append(Entry(sourceID: id, path: sub, name: String(rest[..<slash]), kind: .folder))
                }
            } else if item.isFolder == true {
                if seen.insert(rel).inserted {
                    result.append(Entry(sourceID: id, path: rel, name: String(rest), kind: .folder))
                }
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
        // static=true: o ficheiro original, sem transcodificação.
        return server.appending(path: "Audio/\(itemID)/stream.\(ext)").appending(queryItems: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token),
        ])
    }

    // MARK: Árvore de pastas

    /// Caminho relativo de um item: a parte do `Path` abaixo da pasta-âncora ou, sem ela, o último nome.
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

    /// A pasta conhecida mais próxima de `path`. Depois de reabrir a app os ids não estão em memória:
    /// lista cada nível desde a raiz até os encontrar.
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
            URLQueryItem(name: "fields", value: "Path"),
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

    private func get(_ path: String, _ query: [URLQueryItem], retry: Bool = true) async throws -> [Item] {
        let session = try await currentSession()
        var request = URLRequest(url: server.appending(path: path).appending(queryItems: query))
        request.setValue(Self.authorization(deviceID: deviceID, token: session.token), forHTTPHeaderField: "Authorization")
        let (data, status) = try await Self.send(request, urlSession)
        if status == 401, retry {
            // Token revogado ou expirado: entra de novo com a palavra-passe guardada.
            self.session = nil
            return try await get(path, query, retry: false)
        }
        guard (200..<300).contains(status) else { throw HTTPError.status(status) }
        guard let decoded = try? JSONDecoder().decode(Items.self, from: data) else { throw SourceError.unexpectedResponse }
        return decoded.items
    }

    private func currentSession() async throws -> Session {
        if let session { return session }
        guard let password = password() else { throw SourceError.loginFailed }
        let fresh = try await Self.login(
            server: server, username: username, password: password, deviceID: deviceID, urlSession: urlSession)
        session = fresh
        return fresh
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
            switch self { case .status(let code): "O servidor respondeu \(code). Tentar de novo" }
        }
    }
}
