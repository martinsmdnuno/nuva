package pt.nunomartins.nuva.ui

import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Ballistics, like a hardware meter: a column rises to the level (at once, or over `attack` seconds)
 * and falls at a steady rate; the peak holds for a moment, then falls too (steadily, or faster and
 * faster with `gravity`). The Mac app's `SpectrumMeter`. Times are in seconds.
 */
class SpectrumMeter(
    count: Int = 10,
    val floor: Float = -54f,
    val ceiling: Float = -6f,
    private val fall: Float = 1.6f,
    private val attack: Float = 0f,
    private val gravity: Float = 0f,
) {
    companion object {
        const val PEAK_FALL = 0.6f
        const val PEAK_HOLD = 0.8
    }

    val levels = FloatArray(count)
    val peaks = FloatArray(count)
    private val peakTimes = DoubleArray(count) { Double.NEGATIVE_INFINITY }
    private val peakSpeeds = FloatArray(count)
    private var last: Double? = null

    /** `measured` in dBFS per column, or null when nothing plays (the columns fall). */
    fun update(now: Double, measured: FloatArray?) {
        val dt = min(max(now - (last ?: now), 0.0), 0.1).toFloat()
        last = now
        for (b in levels.indices) {
            val target = measured?.let { ((it[b] - floor) / (ceiling - floor)).coerceIn(0f, 1f) } ?: 0f
            levels[b] = if (target > levels[b]) {
                if (attack > 0) levels[b] + (target - levels[b]) * min(1f, dt / attack) else target
            } else {
                max(target, levels[b] - fall * dt)
            }
            if (levels[b] >= peaks[b]) {
                peaks[b] = levels[b]
                peakTimes[b] = now
                peakSpeeds[b] = 0f
            } else if (now - peakTimes[b] > PEAK_HOLD) {
                if (gravity > 0) {
                    peakSpeeds[b] += gravity * dt
                    peaks[b] = max(levels[b], peaks[b] - peakSpeeds[b] * dt)
                } else {
                    peaks[b] = max(levels[b], peaks[b] - PEAK_FALL * dt)
                }
            }
        }
    }
}

/** Left and right with their own ballistics: `levels` is what the face draws, `peaks` the last half second's highest, in dBFS. */
interface StereoMeter {
    val levels: FloatArray
    val peaks: FloatArray
    /** `measured`: RMS L, RMS R, peak L, peak R in dBFS, or null when nothing plays. */
    fun update(now: Double, measured: FloatArray?)
}

/** Slow ballistics for the valves' filaments: they rise and fall over a fraction of a second, like a heater. */
class SlowMeter(private val floor: Float, private val ceiling: Float, private val rise: Float, private val fall: Float) : StereoMeter {
    override val levels = FloatArray(2)
    override val peaks = FloatArray(2) { -120f }
    private val peakTimes = DoubleArray(2) { Double.NEGATIVE_INFINITY }
    private var last: Double? = null

    override fun update(now: Double, measured: FloatArray?) {
        val dt = min(max(now - (last ?: now), 0.0), 0.1).toFloat()
        last = now
        for (c in 0..1) {
            val target = measured?.let { ((it[c] - floor) / (ceiling - floor)).coerceIn(0f, 1f) } ?: 0f
            val rate = if (target > levels[c]) rise else fall
            levels[c] += (target - levels[c]) * min(1f, rate * dt)
            val peak = measured?.get(c + 2)
            if (peak != null && peak >= peaks[c]) {
                peaks[c] = peak
                peakTimes[c] = now
            } else if (now - peakTimes[c] > 0.5) {
                peaks[c] = peak ?: -120f
            }
        }
    }
}

/**
 * A VU meter's movement: a needle on a damped spring, driven by the signal's voltage. Tuned to the
 * standard (IEC 60268-17): 99% of a steady tone's reading in 300 ms, about 1.2% overshoot. It rests on
 * a pin left of the scale and bounces softly off the pins. The Mac app's `VUNeedle`.
 */
class VUNeedle {
    companion object {
        const val FREQUENCY = 13.5
        const val DAMPING = 0.81
        const val END_STOP = 1.08
        const val BOUNCE = 0.2

        /** Deflection for a level in VU: proportional to voltage, 1 at +3 VU. */
        fun deflection(vu: Double) = 10.0.pow((vu - 3) / 20)
    }

    var position = 0.0
        private set
    private var velocity = 0.0

    /** Moves `dt` seconds towards `target`, in 1 ms steps so it is stable at any frame rate. */
    fun step(target: Double, dt: Double) {
        val w = FREQUENCY
        val z = DAMPING
        var remaining = dt.coerceIn(0.0, 0.25)
        while (remaining > 0) {
            val h = min(remaining, 0.001)
            velocity += (w * w * (target - position) - 2 * z * w * velocity) * h
            position += velocity * h
            if (position < 0) {
                position = 0.0
                velocity = -velocity * BOUNCE
            } else if (position > END_STOP) {
                position = END_STOP
                velocity = -velocity * BOUNCE
            }
            remaining -= h
        }
    }
}

/** Two needles fed from the RMS levels; 0 VU is -14 dBFS RMS. Peaks held half a second, for the peak light. */
class NeedleMeter : StereoMeter {
    companion object {
        const val REFERENCE = -14f
    }

    private val needles = arrayOf(VUNeedle(), VUNeedle())
    override val levels = FloatArray(2)
    override val peaks = FloatArray(2) { -120f }
    private val peakTimes = DoubleArray(2) { Double.NEGATIVE_INFINITY }
    private var last: Double? = null

    override fun update(now: Double, measured: FloatArray?) {
        val dt = now - (last ?: now)
        last = now
        for (c in 0..1) {
            val target = measured?.let { VUNeedle.deflection((it[c] - REFERENCE).toDouble()) } ?: 0.0
            needles[c].step(target, dt)
            levels[c] = needles[c].position.toFloat()
            val peak = measured?.get(c + 2)
            if (peak != null && peak >= peaks[c]) {
                peaks[c] = peak
                peakTimes[c] = now
            } else if (now - peakTimes[c] > 0.5) {
                peaks[c] = peak ?: -120f
            }
        }
    }
}
