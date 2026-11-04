package pt.nunomartins.nuva.player

/**
 * What the quality badge says: "FLAC 905 kbps | 16-bit/44.1 kHz", "MP3 320 kbps | 44.1 kHz". The
 * bitrate is the file's average (its size over its length), as the Mac and Windows show it; the stream
 * is always the original file, so this is what is heard.
 */
data class Quality(val codec: String, val bits: Int?, val sampleRate: Int?, val kbps: Int?) {
    val label: String get() = text(compact = false)

    /** For the player's smaller display: "FLAC 905 kbps | 16/44.1", the units the full label spells out left off. */
    val compactLabel: String get() = text(compact = true)

    private fun text(compact: Boolean): String {
        val left = listOfNotNull(codec.ifEmpty { null }, kbps?.let { "$it kbps" }).joinToString(" ")
        val rate = sampleRate?.takeIf { it > 0 }?.let { if (compact) kHz(it) else "${kHz(it)} kHz" }
        val right = when {
            bits != null && rate != null -> if (compact) "$bits/$rate" else "$bits-bit/$rate"
            rate != null && compact -> "$rate kHz"
            else -> rate
        }
        return listOfNotNull(left.ifEmpty { null }, right).joinToString(" | ")
    }

    companion object {
        /** 44100 → "44.1", 48000 → "48". */
        fun kHz(rate: Int): String {
            val k = rate / 1000.0
            return if (k % 1.0 == 0.0) k.toInt().toString() else "%.1f".format(java.util.Locale.ROOT, k)
        }

        /** Average kbps of a file of `bytes` lasting `seconds`; null when either isn't known. */
        fun kbps(bytes: Long?, seconds: Double?): Int? {
            if (bytes == null || bytes <= 0 || seconds == null || seconds <= 0) return null
            return Math.round(bytes * 8 / seconds / 1000).toInt()
        }
    }
}
