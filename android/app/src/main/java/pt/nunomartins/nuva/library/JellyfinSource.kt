package pt.nunomartins.nuva.library


import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import pt.nunomartins.nuva.artwork.FolderArtwork
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * A Jellyfin server, browsed by its disk folders (each item's `Path`), never by Jellyfin's
 * artists and albums. Plays the original file, without conversion. A port of the Mac app's
 * `JellyfinSource.swift`; keep the two in step.
 */
class JellyfinSource(
    val server: String,
    private val session: Session,
    private val deviceId: String,
    private val version: String,
) {
    data class Session(val token: String, val userId: String)

    data class Item(
        val id: String,
        val name: String?,
        val isFolder: Boolean,
        val path: String?,
        val container: String?,
        val runTimeTicks: Long?,
        val collectionType: String?,
        /** The file's size, from its first media source. */
        val size: Long? = null,
    ) {
        /** Path with forward slashes (Windows servers use `\`). */
        val unixPath: String? get() = path?.replace('\\', '/')

        companion object {
            fun from(json: JSONObject) = Item(
                id = json.getString("Id"),
                name = json.optStringOrNull("Name"),
                isFolder = json.optBoolean("IsFolder", false),
                path = json.optStringOrNull("Path"),
                container = json.optStringOrNull("Container"),
                runTimeTicks = if (json.has("RunTimeTicks") && !json.isNull("RunTimeTicks")) json.getLong("RunTimeTicks") else null,
                collectionType = json.optStringOrNull("CollectionType"),
                size = json.optJSONArray("MediaSources")?.optJSONObject(0)?.let { if (it.has("Size") && !it.isNull("Size")) it.getLong("Size") else null },
            )
        }
    }

    /** A known folder: its item id and its path on the server's disk (null at a library root). */
    private data class Node(val id: String, val abs: String?)

    private val lock = Mutex()
    private var legacyRoutes = false
    private var rootLoaded = false
    private var libraries: List<Item> = emptyList()
    private val nodes = mutableMapOf<String, Node>()
    private val tracks = mutableMapOf<String, String>()
    private val listed = mutableSetOf<String>()

    /** Folders and tracks in `path` ("" is the root), folders first, in natural order. */
    suspend fun list(path: String): List<Entry> = lock.withLock { listLocked(path) }

    /** The stream of the original file: `static=true` means no transcoding, so a FLAC stays a FLAC. */
    suspend fun url(track: Entry): String = lock.withLock {
        if (tracks[track.path] == null) listLocked(track.parentPath)
        val id = tracks[track.path] ?: throw SourceException(SourceException.Reason.MissingFolder)
        val ext = track.name.substringAfterLast('.', "").lowercase()
        "$server/Audio/$id/stream.$ext?static=true&api_key=${session.token.encoded()}"
    }

    /**
     * The image file the user put in `folder` on the server (cover.jpg, folder.png…, as on the Mac),
     * as Jellyfin serves it; null when there is none. Only an image whose file is in the folder itself
     * counts: never one Jellyfin took from the tags or downloaded (folders, not metadata).
     */
    suspend fun folderArtwork(folder: String): ByteArray? = lock.withLock {
        if (!rootLoaded) loadRoot()
        val (rel, node) = try {
            anchor(folder)
        } catch (e: SourceException) {
            return@withLock null
        }
        val abs = node.abs ?: return@withLock null
        if (rel != folder) return@withLock null
        val auth = authorization(deviceId, version, session.token)
        val (status, body) = send("GET", "$server/Items/${node.id}/Images", auth, null)
        if (status == 401) throw SourceException(SourceException.Reason.LoginFailed, status)
        if (status !in 200..299) return@withLock null
        val images = try {
            JSONArray(body).objects().map { FolderArtwork.Image(it.optString("ImageType"), it.optStringOrNull("Path"), if (it.has("ImageIndex") && !it.isNull("ImageIndex")) it.getInt("ImageIndex") else null) }
        } catch (e: Exception) {
            return@withLock null
        }
        val image = FolderArtwork.choose(images, abs) ?: return@withLock null
        val index = image.index?.let { "/$it" }.orEmpty()
        val (imageStatus, bytes) = sendBytes("GET", "$server/Items/${node.id}/Images/${image.type}$index?maxWidth=800&quality=90", auth)
        if (imageStatus !in 200..299 || bytes.isEmpty()) null else bytes
    }

    private suspend fun listLocked(path: String): List<Entry> {
        if (!rootLoaded) loadRoot()
        if (path.isEmpty() && libraries.isNotEmpty()) {
            listed.add("")
            return libraries.map { Entry(it.name ?: it.id, it.name ?: it.id, isFolder = true) }.naturallySorted()
        }
        val (anchorRel, anchor) = anchor(path)
        val placed = items(anchor.id).map { it to register(it, anchorRel, anchor.abs) }
        listed.add(path)

        // Direct children of `path`; deeper items (an album with CD1/CD2) yield folders from the path.
        val result = mutableListOf<Entry>()
        val seen = mutableSetOf<String>()
        val prefix = if (path.isEmpty()) "" else "$path/"
        for ((item, rel) in placed) {
            if (!rel.startsWith(prefix)) continue
            val rest = rel.substring(prefix.length)
            val slash = rest.indexOf('/')
            when {
                slash >= 0 -> {
                    val sub = prefix + rest.substring(0, slash)
                    if (seen.add(sub)) result.add(Entry(sub, rest.substring(0, slash), isFolder = true))
                }
                item.isFolder -> if (seen.add(rel)) result.add(Entry(rel, rest, isFolder = true))
                Playable.isPlayable(rel) ->
                    result.add(Entry(rel, rest, isFolder = false, duration = item.runTimeTicks?.let { it / 10_000_000.0 }, size = item.size))
            }
        }
        return result.naturallySorted()
    }

    private fun register(item: Item, anchorRel: String, anchorAbs: String?): String {
        val rel = relativePath(item, anchorRel, anchorAbs)
        if (item.isFolder) nodes[rel] = Node(item.id, item.unixPath) else tracks[rel] = item.id
        return rel
    }

    /** The closest known folder to `path`; lists each level from the root until it is found. */
    private suspend fun anchor(path: String): Pair<String, Node> {
        var prefix = ""
        for (part in path.split('/').filter { it.isNotEmpty() }) {
            val next = if (prefix.isEmpty()) part else "$prefix/$part"
            if (nodes[next] == null && prefix !in listed) listLocked(prefix)
            prefix = next
        }
        var p = path
        while (true) {
            nodes[p]?.let { return p to it }
            if (p.isEmpty()) throw SourceException(SourceException.Reason.MissingFolder)
            p = p.substringBeforeLast('/', "")
        }
    }

    private suspend fun loadRoot() {
        val views = userViews().filter { it.collectionType == "music" }
        if (views.isEmpty()) throw SourceException(SourceException.Reason.NoMusicLibrary)
        if (views.size == 1) {
            nodes[""] = Node(views[0].id, null)
        } else {
            libraries = views
            for (view in views) nodes[view.name ?: view.id] = Node(view.id, null)
        }
        rootLoaded = true
    }

    private suspend fun userViews(): List<Item> {
        if (!legacyRoutes) {
            try {
                return get("UserViews", mapOf("userId" to session.userId))
            } catch (e: SourceException) {
                if (e.status != 404) throw e
                legacyRoutes = true
            }
        }
        return get("Users/${session.userId}/Views", emptyMap())
    }

    private suspend fun items(parentId: String): List<Item> {
        val query = mapOf("parentId" to parentId, "fields" to "Path,MediaSources", "enableImages" to "false", "enableUserData" to "false")
        if (!legacyRoutes) {
            try {
                return get("Items", query + ("userId" to session.userId))
            } catch (e: SourceException) {
                if (e.status != 404) throw e
                legacyRoutes = true
            }
        }
        return get("Users/${session.userId}/Items", query)
    }

    private suspend fun get(path: String, query: Map<String, String>): List<Item> {
        val (status, body) = send("GET", "$server/$path?${query.toQuery()}", authorization(deviceId, version, session.token), null)
        if (status == 401) throw SourceException(SourceException.Reason.LoginFailed, status)
        if (status !in 200..299) throw SourceException(SourceException.Reason.HttpStatus, status)
        val items = try {
            JSONObject(body).getJSONArray("Items")
        } catch (e: Exception) {
            throw SourceException(SourceException.Reason.UnexpectedResponse)
        }
        return items.objects().map(Item::from)
    }

    companion object {
        /** Relative path of an item: the part of `Path` below the anchor folder or, without one, the last name. */
        fun relativePath(item: Item, anchorRel: String, anchorAbs: String?): String {
            val path = item.unixPath
            val leaf = when {
                anchorAbs != null && path != null && path.startsWith("$anchorAbs/") -> path.substring(anchorAbs.length + 1)
                path != null -> path.substringAfterLast('/')
                else -> {
                    val name = item.name ?: item.id
                    if (item.isFolder || item.container == null) name else "$name.${item.container}"
                }
            }
            return if (anchorRel.isEmpty()) leaf else "$anchorRel/$leaf"
        }

        /** Signs in and returns the session. The password is used once and never kept. */
        suspend fun login(server: String, username: String, password: String, deviceId: String, version: String): Session {
            val body = JSONObject().put("Username", username).put("Pw", password).toString()
            val (status, response) = send("POST", "$server/Users/AuthenticateByName", authorization(deviceId, version, null), body)
            if (status == 401 || status == 403) throw SourceException(SourceException.Reason.LoginFailed, status)
            if (status !in 200..299) throw SourceException(SourceException.Reason.HttpStatus, status)
            return try {
                val json = JSONObject(response)
                Session(json.getString("AccessToken"), json.getJSONObject("User").getString("Id"))
            } catch (e: Exception) {
                throw SourceException(SourceException.Reason.UnexpectedResponse)
            }
        }

        /**
         * "music.example.com/" → "https://music.example.com". Without a scheme, Jellyfin's own
         * plain-HTTP port (8096) means http, so "192.168.1.2:8096" works as typed with a remote.
         */
        fun normalise(address: String): String {
            val trimmed = address.trim().trimEnd('/')
            if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed
            return if (trimmed.substringAfterLast(':', "") == "8096") "http://$trimmed" else "https://$trimmed"
        }

        private fun authorization(deviceId: String, version: String, token: String?): String {
            var value = """MediaBrowser Client="NuVa", Device="Android TV", DeviceId="$deviceId", Version="$version""""
            if (token != null) value += """, Token="$token""""
            return value
        }

        private suspend fun send(method: String, url: String, authorization: String, body: String?): Pair<Int, String> =
            sendBytes(method, url, authorization, body).let { (status, bytes) -> status to String(bytes) }

        private suspend fun sendBytes(method: String, url: String, authorization: String, body: String? = null): Pair<Int, ByteArray> =
            withContext(Dispatchers.IO) {
                try {
                    val connection = URL(url).openConnection() as HttpURLConnection
                    connection.requestMethod = method
                    connection.connectTimeout = 15_000
                    connection.readTimeout = 30_000
                    connection.setRequestProperty("Authorization", authorization)
                    connection.setRequestProperty("Accept", "application/json")
                    if (body != null) {
                        connection.doOutput = true
                        connection.setRequestProperty("Content-Type", "application/json")
                        connection.outputStream.use { it.write(body.toByteArray()) }
                    }
                    val status = connection.responseCode
                    val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                    val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
                    connection.disconnect()
                    status to bytes
                } catch (e: IOException) {
                    throw SourceException(SourceException.Reason.ServerUnavailable)
                }
            }
    }
}

private fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

private fun String.encoded(): String = URLEncoder.encode(this, "UTF-8")

private fun Map<String, String>.toQuery(): String = entries.joinToString("&") { "${it.key.encoded()}=${it.value.encoded()}" }
