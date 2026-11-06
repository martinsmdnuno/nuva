package pt.nunomartins.nuva.artwork

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import pt.nunomartins.nuva.library.Entry
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.Normalizer
import kotlin.math.pow
import kotlin.math.sqrt

/** Artist and album to look up online, read from folder names (never from tags). */
data class AlbumQuery(val artist: String, val album: String) {
    /** Shared by every folder with the same artist and album. */
    val key: String get() = "${AlbumGuess.normalize(artist)}|${AlbumGuess.normalize(album)}"

    /** Without a title before the artist ("Ms. Lauryn Hill" → "Lauryn Hill"); tried only after the full name finds nothing. */
    val withoutTitle: AlbumQuery?
        get() = Regex("""^(?i:ms|mrs|mr|miss|dr|sir|dame)\.?\s+(.+)$""").find(artist)?.let { AlbumQuery(it.groupValues[1], album) }
}

/** The Mac app's `AlbumGuess`: artist and album from "Artist/Album (1977)/CD 01". */
object AlbumGuess {
    fun from(path: String): AlbumQuery? {
        val parts = path.split('/').filter { it.isNotEmpty() }.toMutableList()
        while (parts.isNotEmpty() && isDiscFolder(parts.last())) parts.removeAt(parts.lastIndex)
        val folder = parts.lastOrNull() ?: return null
        if (parts.size == 1 || isGeneric(parts[parts.size - 2])) {
            val pieces = folder.split(" - ")
            return if (pieces.size >= 2) valid(clean(pieces[0]), clean(pieces.drop(1).joinToString(" - "))) else null
        }
        var album = clean(folder)
        val artist = clean(parts[parts.size - 2])
        if (album.startsWith("$artist - ", ignoreCase = true)) album = album.substring(artist.length + 3)
        return valid(artist, album)
    }

    private fun valid(artist: String, album: String) = if (artist.isEmpty() || album.isEmpty()) null else AlbumQuery(artist, album)

    fun isDiscFolder(name: String) = Regex("""^(cd|disc|disk|disco)[\s._-]*\d+\b""", RegexOption.IGNORE_CASE).containsMatchIn(name)

    fun isGeneric(name: String) =
        name.lowercase() in setOf("music", "música", "musica", "flac", "mp3", "albums", "álbuns", "albuns", "library", "biblioteca")

    /** "1977 - Rumours (Remastered) [FLAC 24-96]" → "Rumours". */
    fun clean(name: String): String {
        var s = name.replace('_', ' ')
        s = s.replace(Regex("""\s*[(\[{][^)\]}]*[)\]}]"""), "")
        s = s.replace(Regex("""^\s*(19|20)\d{2}\s*[-–.]\s*"""), "")
        s = s.replace(Regex("""(\s*[-–]?\s*((19|20)\d{2}|flac|mp3|alac|wav|hi-?res|24[\s-]?bit|\d{2}[-/]\d{2,3}))+\s*$""", RegexOption.IGNORE_CASE), "")
        return s.trim(' ', '-', '–', '.')
    }

    /** For comparing: lowercase, no accents or punctuation, "&" as "and", no leading "the". */
    fun normalize(s: String): String {
        var t = Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD).replace(Regex("""\p{M}"""), "")
        t = t.replace("&", " and ")
        t = t.replace(Regex("""[^a-z0-9 ]"""), "")
        t = t.replace(Regex("""\s+"""), " ").trim()
        if (t.startsWith("the ")) t = t.substring(4)
        return t
    }
}

/**
 * Album covers from MusicBrainz (finds the album) and the Cover Art Archive (serves the image). Open
 * data, no key. Only confident matches count: a wrong cover is worse than none.
 */
class CoverArtArchive(private val version: String) {
    data class ReleaseGroup(val id: String, val score: Int, val title: String, val artist: String)

    class HttpStatus(val code: Int) : IOException("HTTP $code")

    private val lock = Mutex()
    private var lastRequest = 0L

    /** JPEG bytes of the front cover (500 px), or null when the album isn't found with confidence. Throws when offline. */
    suspend fun cover(query: AlbumQuery): ByteArray? {
        for (group in search(query)) {
            if (!matches(group, query)) continue
            front(group.id)?.let { return it }
        }
        return null
    }

    private suspend fun search(query: AlbumQuery): List<ReleaseGroup> {
        val lucene = "releasegroup:\"${escape(query.album)}\" AND artist:\"${escape(query.artist)}\""
        val url = "https://musicbrainz.org/ws/2/release-group/?query=${URLEncoder.encode(lucene, "UTF-8")}&fmt=json&limit=5"
        val (status, body, _) = get(url, "application/json")
        if (status != 200) throw HttpStatus(status)
        val groups = JSONObject(String(body)).optJSONArray("release-groups") ?: return emptyList()
        return (0 until groups.length()).map { i ->
            val g = groups.getJSONObject(i)
            val credits = g.optJSONArray("artist-credit")
            val artist = (0 until (credits?.length() ?: 0)).joinToString(" ") { credits!!.getJSONObject(it).optString("name") }
            ReleaseGroup(g.getString("id"), g.optInt("score"), g.optString("title"), artist)
        }
    }

    private suspend fun front(id: String): ByteArray? {
        val (status, body, type) = get("https://coverartarchive.org/release-group/$id/front-500", null)
        if (status == 404) return null
        if (status != 200) throw HttpStatus(status)
        return if (type?.startsWith("image/") == true) body else null
    }

    /** At most one request a second (MusicBrainz's rule), with an identifying User-Agent; follows redirects. */
    private suspend fun get(address: String, accept: String?): Triple<Int, ByteArray, String?> = lock.withLock {
        val wait = 1100 - (System.currentTimeMillis() - lastRequest)
        if (wait > 0) delay(wait)
        lastRequest = System.currentTimeMillis()
        withContext(Dispatchers.IO) {
            var url = address
            repeat(5) {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 15_000
                c.readTimeout = 15_000
                c.instanceFollowRedirects = false
                c.setRequestProperty("User-Agent", "NuVa-AndroidTV/$version ( https://github.com/martinsmdnuno/nuva )")
                if (accept != null) c.setRequestProperty("Accept", accept)
                val status = c.responseCode
                if (status in 300..399) {
                    url = URL(URL(url), c.getHeaderField("Location")).toString()
                    c.disconnect()
                    return@repeat
                }
                val body = (if (status in 200..299) c.inputStream else c.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
                val type = c.contentType
                c.disconnect()
                return@withContext Triple(status, body, type)
            }
            throw IOException("Too many redirects")
        }
    }

    companion object {
        /** High MusicBrainz score, same artist and same album title once normalised. */
        fun matches(group: ReleaseGroup, query: AlbumQuery): Boolean {
            if (group.score < 90) return false
            val artist = AlbumGuess.normalize(query.artist)
            val album = AlbumGuess.normalize(query.album)
            val foundArtist = AlbumGuess.normalize(group.artist)
            val foundAlbum = AlbumGuess.normalize(group.title)
            val sameArtist = foundArtist == artist || foundArtist.startsWith("$artist ") || artist.startsWith("$foundArtist ")
            val sameAlbum = foundAlbum == album || AlbumGuess.normalize(AlbumGuess.clean(group.title)) == album
            return sameArtist && sameAlbum
        }

        fun escape(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")
    }
}

/** The image files that count as a folder's artwork, as the Mac's `Artwork`: "cover", "folder", "front", "album", "capa" (Portuguese) · jpg, jpeg, png. */
object FolderArtwork {
    val names = listOf("cover", "folder", "front", "album", "capa")
    val extensions = setOf("jpg", "jpeg", "png")

    /** One of a server item's images: its type ("Primary"), the file it was read from, its index. */
    data class Image(val type: String, val path: String?, val index: Int?)

    /** Rank of a file name among `names` (0 is best), or null when it isn't artwork. Case-insensitive. */
    fun rank(fileName: String): Int? {
        if (fileName.substringAfterLast('.', "").lowercase() !in extensions) return null
        return names.indexOf(fileName.substringBeforeLast('.').lowercase()).takeIf { it >= 0 }
    }

    /** The best image whose file sits in `folder` itself (the server's path, `/` or `\`) and is named as artwork. */
    fun choose(images: List<Image>, folder: String): Image? {
        val dir = folder.replace('\\', '/').trimEnd('/')
        return images
            .mapNotNull { image ->
                val path = image.path?.replace('\\', '/') ?: return@mapNotNull null
                if (path.substringBeforeLast('/') != dir) return@mapNotNull null
                rank(path.substringAfterLast('/'))?.let { image to it }
            }
            .minByOrNull { it.second }?.first
    }
}

/** Where a cover came from, as the Mac's `ArtworkOrigin`, or why there is none. */
enum class ArtworkOrigin { Folder, Online, None, Offline }

data class ResolvedArtwork(val cover: Bitmap?, val origin: ArtworkOrigin)

/**
 * Finds a folder's cover: the image file in the folder on the server first (a disc folder also looks
 * in its album folder), then online from its names, kept in the app's own files (never in the music
 * folders). An online miss is remembered for 14 days; an error (offline) isn't remembered at all.
 * Each album's outcome goes to the log ("NuVa.Artwork"), step by step.
 */
class ArtworkResolver(
    private val root: File,
    private val online: CoverArtArchive,
    private val folderImage: suspend (String) -> ByteArray?,
) {
    private val missLifetime = 14L * 24 * 3600 * 1000

    suspend fun resolve(track: Entry): ResolvedArtwork = withContext(Dispatchers.IO) {
        val steps = mutableListOf<String>()
        fun done(result: ResolvedArtwork): ResolvedArtwork {
            android.util.Log.i("NuVa.Artwork", "${track.albumPath}: ${steps.joinToString(", ")} → ${result.origin}")
            return result
        }
        var offline = false
        var folder = track.parentPath
        while (true) {
            val data = try {
                folderImage(folder)
            } catch (e: Exception) {
                offline = true
                null
            }
            val image = data?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            steps += "folder ${folder.substringAfterLast('/')}: ${if (image != null) "found" else if (offline) "unreachable" else "none"}"
            if (image != null) return@withContext done(ResolvedArtwork(image, ArtworkOrigin.Folder))
            if (!AlbumGuess.isDiscFolder(folder.substringAfterLast('/'))) break
            folder = folder.substringBeforeLast('/', "")
        }
        val query = AlbumGuess.from(folder)
        if (query == null) {
            steps += "online: no artist and album in the folder names"
            return@withContext done(ResolvedArtwork(null, if (offline) ArtworkOrigin.Offline else ArtworkOrigin.None))
        }
        for (candidate in listOfNotNull(query, query.withoutTitle)) {
            val base = file(candidate.key)
            val jpg = File("$base.jpg")
            val miss = File("$base.none")
            if (jpg.exists()) {
                steps += "online \"${candidate.artist} / ${candidate.album}\": kept"
                return@withContext done(ResolvedArtwork(BitmapFactory.decodeFile(jpg.path), ArtworkOrigin.Online))
            }
            if (miss.exists() && System.currentTimeMillis() - miss.lastModified() < missLifetime) {
                steps += "online \"${candidate.artist} / ${candidate.album}\": not found before"
                continue
            }
            val data = try {
                online.cover(candidate)
            } catch (e: Exception) {
                steps += "online \"${candidate.artist} / ${candidate.album}\": unreachable (${e.message})"
                return@withContext done(ResolvedArtwork(null, ArtworkOrigin.Offline))
            }
            jpg.parentFile?.mkdirs()
            if (data != null) {
                jpg.writeBytes(data)
                miss.delete()
                steps += "online \"${candidate.artist} / ${candidate.album}\": found"
                return@withContext done(ResolvedArtwork(BitmapFactory.decodeByteArray(data, 0, data.size), ArtworkOrigin.Online))
            }
            steps += "online \"${candidate.artist} / ${candidate.album}\": no confident match"
            miss.writeBytes(ByteArray(0))
        }
        done(ResolvedArtwork(null, if (offline) ArtworkOrigin.Offline else ArtworkOrigin.None))
    }

    private fun file(key: String): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(root, "online/${hash.take(32)}").path
    }
}

/**
 * Ambient mode's glow from the cover: the cover reduced to a 4×4 grid of its own colours, each
 * darkened until the display's muted text keeps 4.5:1 on it, then blurred into a soft field that keeps
 * the cover's layout, falling towards the display's colour at the edges (see `GlowField`). The Mac app's `ArtworkGlow`.
 */
object ArtworkGlow {
    private const val GRID = 4

    fun field(cover: Bitmap, display: Int, muted: Int): GlowField? {
        val ceiling = (luminance(muted) + 0.05) / 4.5 - 0.05
        if (ceiling <= luminance(display) + 0.002) return null
        val small = Bitmap.createScaledBitmap(cover, GRID * 4, GRID * 4, true)
        val cells = IntArray(GRID * GRID) { cell ->
            val row = cell / GRID
            val column = cell % GRID
            var r = 0.0; var g = 0.0; var b = 0.0
            for (y in row * 4 until row * 4 + 4) for (x in column * 4 until column * 4 + 4) {
                val p = small.getPixel(x, y)
                r += Color.red(p); g += Color.green(p); b += Color.blue(p)
            }
            Color.rgb((r / 16).toInt(), (g / 16).toInt(), (b / 16).toInt())
        }
        val brightest = cells.maxOf { luminance(it) }
        val safe = ceiling * 0.95
        val shaded = cells.map { shade(it, if (brightest > 0) luminance(it) / brightest else 0.0, safe) }

        return GlowField(shaded.toIntArray(), display)
    }

    /** The glow's images: the field (dimmed, so the lights have room) and one soft light per moving light. */
    class Images(val base: Bitmap, val lights: List<Bitmap>)

    /**
     * The field at `width`×`height` pixels (the screen's own size, drawn one to one), and its lights,
     * each `lightSize` across at half resolution (drawn twice as large).
     */
    fun render(field: GlowField, width: Int, height: Int, lightSize: Int): Images {
        val base = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        field.render(width, height, BASE_DIM) { y, row -> base.setPixels(row, 0, width, 0, y, width, 1) }
        val half = (lightSize / 2).coerceAtLeast(2)
        val lights = field.lightColours(GlowMotion.PARTS).map { colour ->
            // Premultiplied bytes as they are, so the dither on alpha and colour survives.
            val bytes = java.nio.ByteBuffer.allocate(half * half * 4)
            GlowField.renderLight(colour, half) { _, row ->
                for (p in row) {
                    bytes.put((p shr 16).toByte()); bytes.put((p shr 8).toByte()); bytes.put(p.toByte()); bytes.put((p ushr 24).toByte())
                }
            }
            bytes.rewind()
            Bitmap.createBitmap(half, half, Bitmap.Config.ARGB_8888).apply { copyPixelsFromBuffer(bytes) }
        }
        return Images(base, lights)
    }

    /** How far the field is moved towards the display's colour: the lights bring the contrast back with the music. */
    const val BASE_DIM = 0.6f

    /**
     * The glow for an album without a cover: the skin's own light (its LED colour) as a soft spot left
     * of centre, fading into the display, through the same shading as a cover's field.
     */
    fun skinField(display: Int, muted: Int, led: Int): GlowField? {
        val side = GRID * 4
        val pixels = IntArray(side * side) { i ->
            val x = (i % side + 0.5) / side
            val y = (i / side + 0.5) / side
            val d = sqrt((x - 0.38) * (x - 0.38) + (y - 0.45) * (y - 0.45))
            val k = (1 - d / 0.75).coerceIn(0.0, 1.0)
            fun mix(channel: (Int) -> Int) = (channel(led) * k + channel(display) * (1 - k)).toInt().coerceIn(0, 255)
            Color.rgb(mix(Color::red), mix(Color::green), mix(Color::blue))
        }
        return field(Bitmap.createBitmap(pixels, side, side, Bitmap.Config.ARGB_8888), display, muted)
    }

    /** The colour's hue, a little more saturated, at a luminance from 40% of `ceiling` (darkest parts) to all of it. */
    private fun shade(color: Int, relative: Double, ceiling: Double): Int {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        val saturation = minOf(0.9f, hsv[1] * 1.15f)
        val target = ceiling * (0.4 + 0.6 * relative.coerceIn(0.0, 1.0))
        var low = 0.0
        var high = 1.0
        repeat(20) {
            val middle = (low + high) / 2
            if (luminance(Color.HSVToColor(floatArrayOf(hsv[0], saturation, middle.toFloat()))) > target) high = middle else low = middle
        }
        return Color.HSVToColor(floatArrayOf(hsv[0], saturation, low.toFloat()))
    }

    /** WCAG relative luminance. */
    fun luminance(color: Int): Double {
        fun linear(v: Int): Double {
            val c = v / 255.0
            return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(Color.red(color)) + 0.7152 * linear(Color.green(color)) + 0.0722 * linear(Color.blue(color))
    }
}
