package pt.nunomartins.nuva.artwork

import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin

/**
 * How the glow's lights move with the music. Three lights, one per part of the spectrum: bass,
 * middle and treble. Each one's brightness follows its part (quick to swell, slower to settle), and
 * all of them travel on slow, never-repeating paths over the screen whose speed follows the music's
 * overall loudness: crawling when quiet or paused, sweeping when loud. Plain Kotlin, tested without Android.
 */
class GlowMotion {
    /** A light: its centre as a fraction of the screen, and its strength (0–1). */
    data class Light(val x: Float, val y: Float, val strength: Float)

    private val parts = DoubleArray(PARTS)
    private var energy = 0.0
    private var phase = 0.0
    private var last: Double? = null

    /** The bass's level (0–1), for the field's own breath. */
    val bass get() = parts[0]

    /** Moves time on to `now` (seconds) with the spectrum's 10 bands in dB, or null when nothing plays. */
    fun update(now: Double, bands: FloatArray?): List<Light> {
        val dt = (now - (last ?: now)).coerceIn(0.0, 0.1)
        last = now
        for (part in 0 until PARTS) {
            val target = bands?.let { level(it, part) } ?: 0.0
            val time = if (target > parts[part]) ATTACK[part] else RELEASE[part]
            parts[part] += (target - parts[part]) * (1 - exp(-dt / time))
        }
        val loud = parts.max()
        energy += (loud - energy) * (1 - exp(-dt / if (loud > energy) 1.5 else 3.0))
        phase += dt * (CALM_SPEED + LOUD_SPEED * energy)
        return List(PARTS) { i ->
            val p = PATHS[i]
            Light(
                x = (0.5 + p[0] * sin(p[1] * phase + p[2])).toFloat(),
                y = (0.5 + p[3] * sin(p[4] * phase + p[5])).toFloat(),
                strength = (IDLE + (1 - IDLE) * parts[i]).toFloat(),
            )
        }
    }

    companion object {
        const val PARTS = 3
        /** A light's strength with nothing in its part: the screen never goes flat. */
        const val IDLE = 0.3
        /** Path speed in radians per second, quiet and at full loudness. */
        const val CALM_SPEED = 0.05
        const val LOUD_SPEED = 0.45

        /** Bands per part (31 Hz–125 Hz, 250 Hz–2 kHz, 4–16 kHz) and the dB that count as silence and full. */
        private val BANDS = arrayOf(0..2, 3..6, 7..9)
        private val FLOOR = doubleArrayOf(-42.0, -48.0, -54.0)
        private const val RANGE = 30.0
        private val ATTACK = doubleArrayOf(0.05, 0.08, 0.06)
        private val RELEASE = doubleArrayOf(0.45, 0.6, 0.5)

        /** Each light's path: x amplitude, frequency, phase; y amplitude, frequency, phase. */
        private val PATHS = arrayOf(
            doubleArrayOf(0.28, 0.71, 0.0, 0.22, 0.53, 1.1),
            doubleArrayOf(0.32, 0.43, 2.1, 0.26, 0.67, 0.4),
            doubleArrayOf(0.30, 0.59, 4.0, 0.24, 0.37, 2.7),
        )

        private fun level(bands: FloatArray, part: Int): Double {
            var loudest = -120.0
            for (b in BANDS[part]) loudest = max(loudest, bands[b].toDouble())
            return ((loudest - FLOOR[part]) / RANGE).coerceIn(0.0, 1.0)
        }
    }
}
