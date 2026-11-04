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

/**
 * Finds a folder's cover online from its names and keeps it in the app's own files (never in the
 * music folders). A miss is remembered for 14 days; an error (offline) isn't remembered at all.
 */
class ArtworkResolver(private val root: File, private val online: CoverArtArchive) {
    private val missLifetime = 14L * 24 * 3600 * 1000

    suspend fun resolve(track: Entry): Bitmap? = withContext(Dispatchers.IO) {
        var folder = track.parentPath
        while (AlbumGuess.isDiscFolder(folder.substringAfterLast('/'))) folder = folder.substringBeforeLast('/', "")
        val query = AlbumGuess.from(folder) ?: return@withContext null
        for (candidate in listOfNotNull(query, query.withoutTitle)) {
            val base = file(candidate.key)
            val jpg = File("$base.jpg")
            val miss = File("$base.none")
            if (jpg.exists()) return@withContext BitmapFactory.decodeFile(jpg.path)
            if (miss.exists() && System.currentTimeMillis() - miss.lastModified() < missLifetime) continue
            val data = try {
                online.cover(candidate)
            } catch (e: Exception) {
                return@withContext null
            }
            jpg.parentFile?.mkdirs()
            if (data != null) {
                jpg.writeBytes(data)
                miss.delete()
                return@withContext BitmapFactory.decodeByteArray(data, 0, data.size)
            }
            miss.writeBytes(ByteArray(0))
        }
        null
    }

    private fun file(key: String): String {
        val hash = MessageDigest.getInstance("SHA-256").digest(key.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(root, "online/${hash.take(32)}").path
    }
}

/**
 * Ambient mode's glow from the cover: the cover reduced to a 4×4 grid of its own colours, each
 * darkened until the display's muted text keeps 4.5:1 on it, then blurred into a soft field that keeps
 * the cover's layout, falling towards the display's colour at the edges. The Mac app's `ArtworkGlow`.
 */
object ArtworkGlow {
    private const val GRID = 4

    fun field(cover: Bitmap, display: Int, muted: Int): Bitmap? {
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

        // A small field, blurred: the screen scales it up with smooth filtering.
        val w = 64
        val h = 40
        val field = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            // Bilinear between cell centres, then a vignette towards the display colour.
            val gx = (x + 0.5) / w * GRID - 0.5
            val gy = (y + 0.5) / h * GRID - 0.5
            val x0 = gx.toInt().coerceIn(0, GRID - 1); val x1 = (x0 + 1).coerceAtMost(GRID - 1)
            val y0 = gy.toInt().coerceIn(0, GRID - 1); val y1 = (y0 + 1).coerceAtMost(GRID - 1)
            val fx = (gx - x0).coerceIn(0.0, 1.0); val fy = (gy - y0).coerceIn(0.0, 1.0)
            fun mix(channel: (Int) -> Int): Double {
                val top = channel(shaded[y0 * GRID + x0]) * (1 - fx) + channel(shaded[y0 * GRID + x1]) * fx
                val bottom = channel(shaded[y1 * GRID + x0]) * (1 - fx) + channel(shaded[y1 * GRID + x1]) * fx
                return top * (1 - fy) + bottom * fy
            }
            val dx = (x + 0.5) / w - 0.5
            val dy = ((y + 0.5) / h - 0.5) * h / w
            val d = sqrt(dx * dx + dy * dy)
            val edge = (((d - 0.22) / (0.62 - 0.22)).coerceIn(0.0, 1.0)) * 0.55
            fun out(channel: (Int) -> Int) = (mix(channel) * (1 - edge) + channel(display) * edge).toInt().coerceIn(0, 255)
            field[y * w + x] = Color.rgb(out(Color::red), out(Color::green), out(Color::blue))
        }
        return Bitmap.createBitmap(blur(blur(field, w, h), w, h), w, h, Bitmap.Config.ARGB_8888)
    }

    /** A 5-tap box blur, horizontal then vertical. */
    private fun blur(px: IntArray, w: Int, h: Int): IntArray {
        fun pass(src: IntArray, horizontal: Boolean): IntArray = IntArray(src.size) { i ->
            val x = i % w
            val y = i / w
            var r = 0; var g = 0; var b = 0
            for (k in -2..2) {
                val j = if (horizontal) y * w + (x + k).coerceIn(0, w - 1) else (y + k).coerceIn(0, h - 1) * w + x
                r += Color.red(src[j]); g += Color.green(src[j]); b += Color.blue(src[j])
            }
            Color.rgb(r / 5, g / 5, b / 5)
        }
        return pass(pass(px, true), false)
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
