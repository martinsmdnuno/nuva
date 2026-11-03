package pt.nunomartins.nuva.library

import java.text.Collator
import java.util.Locale

/** A folder or a track inside a source. The path is relative to the source root, with `/`. */
data class Entry(
    val path: String,
    val name: String,
    val isFolder: Boolean,
    /** Seconds, when the server already knows it. */
    val duration: Double? = null,
) {
    /** Uppercase extension, for the display ("FLAC"). */
    val format: String get() = name.substringAfterLast('.', "").uppercase()

    /** Name for lists: a track without its extension (the format is on the display), a folder as it is. */
    val listName: String get() = if (isFolder) name else name.substringBeforeLast('.')

    /** File name without extension or leading number ("01 - ", "1. ", "01_"). */
    val title: String
        get() {
            val base = name.substringBeforeLast('.')
            val stripped = base.replace(Regex("""^\d{1,3}(\s*[-–._)]\s*|\s+)"""), "")
            return stripped.ifEmpty { base }
        }

    val parentPath: String get() = path.substringBeforeLast('/', "")

    /** Name of the folder that holds the entry. */
    val folderName: String get() = parentPath.substringAfterLast('/')

    /** The album's folder: the one holding the track, or the one above a disc folder ("CD 1"). */
    val albumPath: String
        get() {
            var folder = parentPath
            while (Regex("""^(cd|disc|disk|disco)[\s._-]*\d+\b""", RegexOption.IGNORE_CASE).containsMatchIn(folder.substringAfterLast('/'))) {
                folder = folder.substringBeforeLast('/', "")
            }
            return folder
        }

    /** The folder above the album, as it is named: usually the artist. Folders, never tags. */
    val artistFolder: String? get() = albumPath.substringBeforeLast('/', "").substringAfterLast('/').ifEmpty { null }

    /** "Fleetwood Mac · Rumours (1977)": the artist's and the album's folders. */
    val folderLine: String get() = listOfNotNull(artistFolder, albumPath.substringAfterLast('/').ifEmpty { null }).joinToString(" · ")
}

object Playable {
    val extensions = setOf("flac", "mp3", "m4a", "aac", "alac", "wav", "aiff")

    fun isPlayable(name: String) = name.substringAfterLast('.', "").lowercase() in extensions
}

/**
 * Natural order, like Finder (and `localizedStandardCompare` in the Mac app): numbers compare
 * by value, so "2" comes before "10", and letters ignore case and accents.
 */
object NaturalOrder : Comparator<String> {
    private val chunk = Regex("""\d+|\D+""")
    private val collator: Collator = Collator.getInstance(Locale.getDefault()).apply { strength = Collator.SECONDARY }

    override fun compare(a: String, b: String): Int {
        val x = chunk.findAll(a).map { it.value }.toList()
        val y = chunk.findAll(b).map { it.value }.toList()
        for (i in 0 until minOf(x.size, y.size)) {
            val p = x[i]
            val q = y[i]
            val result = if (p[0].isDigit() && q[0].isDigit()) {
                val byValue = p.trimStart('0').length.compareTo(q.trimStart('0').length)
                    .takeIf { it != 0 } ?: p.trimStart('0').compareTo(q.trimStart('0'))
                byValue.takeIf { it != 0 } ?: p.length.compareTo(q.length)
            } else {
                collator.compare(p, q)
            }
            if (result != 0) return result
        }
        return x.size.compareTo(y.size)
    }
}

/** Folders first, then tracks; within each group, natural name order. */
fun List<Entry>.naturallySorted(): List<Entry> =
    sortedWith(compareBy<Entry> { !it.isFolder }.thenBy(NaturalOrder) { it.name })

class SourceException(val reason: Reason, val status: Int = 0) : Exception(reason.name) {
    enum class Reason { ServerUnavailable, LoginFailed, NoMusicLibrary, UnexpectedResponse, MissingFolder, HttpStatus }
}
