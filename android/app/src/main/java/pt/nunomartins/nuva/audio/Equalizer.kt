package pt.nunomartins.nuva.audio

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/** A preset: its key (the Portuguese name, as on the Mac) and the gain in dB of each band. */
data class EqPreset(val key: String, val gains: List<Float>)

/**
 * The 10-band equalizer's state, shared by the screen and the audio thread, saved between launches.
 * Same bands, range and presets as the Mac app's `Equalizer.swift`.
 */
class Equalizer(context: Context) {
    companion object {
        val frequencies = doubleArrayOf(32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0)
        val labels = listOf("32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k")
        const val MIN = -12f
        const val MAX = 12f
        const val CUSTOM = "Personalizado"

        val presets = listOf(
            EqPreset("Plano", listOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)),
            EqPreset("Graves", listOf(6f, 5f, 4f, 2f, 0f, 0f, 0f, 0f, 0f, 0f)),
            EqPreset("Agudos", listOf(0f, 0f, 0f, 0f, 0f, 1f, 2f, 4f, 5f, 6f)),
            EqPreset("Voz", listOf(-2f, -2f, -1f, 1f, 3f, 4f, 3f, 1f, 0f, -1f)),
            EqPreset("Loudness", listOf(6f, 4f, 2f, 0f, -1f, -1f, 0f, 2f, 4f, 5f)),
            EqPreset("Rock", listOf(4f, 3f, 1f, -1f, -2f, -1f, 1f, 3f, 4f, 4f)),
            EqPreset("Clássica", listOf(3f, 2f, 1f, 0f, 0f, 0f, -1f, 1f, 2f, 3f)),
            EqPreset("Noite", listOf(3f, 2f, 1f, 0f, 0f, 0f, -1f, -2f, -3f, -4f)),
        )

        /** Normalised [b0, b1, b2, a1, a2] of a peaking filter (Audio EQ Cookbook, Q 1.41). */
        fun peaking(frequency: Double, gain: Double, sampleRate: Double): DoubleArray {
            if (gain == 0.0 || frequency >= sampleRate / 2) return doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0)
            val a = 10.0.pow(gain / 40)
            val w0 = 2 * Math.PI * frequency / sampleRate
            val alpha = sin(w0) / (2 * 1.41)
            val a0 = 1 + alpha / a
            return doubleArrayOf((1 + alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha / a) / a0)
        }
    }

    private val prefs = context.getSharedPreferences("equalizer", Context.MODE_PRIVATE)

    var gains by mutableStateOf(load())
        private set
    var enabled by mutableStateOf(prefs.getBoolean("enabled", false))
        private set
    /** The active preset's key, or "Personalizado" after changing a band. */
    var preset by mutableStateOf(prefs.getString("preset", presets[0].key) ?: presets[0].key)
        private set

    /** Read by the audio thread on every block; `version` changes with every edit. */
    @Volatile var snapshot = Snapshot(gains.toFloatArray(), enabled, 0)
        private set

    class Snapshot(val gains: FloatArray, val enabled: Boolean, val version: Int)

    fun apply(preset: EqPreset) {
        gains = preset.gains
        this.preset = preset.key
        enabled = true
        push()
    }

    fun toggle() {
        enabled = !enabled
        push()
    }

    /** Moves a band by `steps` half-decibel steps, as a fader would. */
    fun nudge(band: Int, steps: Int) {
        val value = ((gains[band] + steps * 0.5f) * 2).roundToInt() / 2f
        val clamped = value.coerceIn(MIN, MAX)
        if (clamped == gains[band] && enabled) return
        gains = gains.toMutableList().also { it[band] = clamped }
        preset = presets.firstOrNull { it.gains == gains }?.key ?: CUSTOM
        enabled = true
        push()
    }

    private fun push() {
        snapshot = Snapshot(gains.toFloatArray(), enabled, snapshot.version + 1)
        prefs.edit()
            .putString("gains", gains.joinToString(","))
            .putBoolean("enabled", enabled)
            .putString("preset", preset)
            .apply()
    }

    private fun load(): List<Float> {
        val saved = prefs.getString("gains", null)?.split(",")?.mapNotNull { it.toFloatOrNull() }
        return if (saved?.size == frequencies.size) saved else presets[0].gains
    }
}

/**
 * 10 cascaded peaking filters per channel on interleaved float samples, with a negative pre-gain so
 * boosts never clip. Rebuilt only when the gains change.
 */
class EqFilter {
    private var version = -1
    private var sampleRate = 0
    private var channels = 0
    private var coefficients = Array(0) { DoubleArray(5) }
    /** Per channel and section: the two state values of a transposed direct form II biquad. */
    private var state = DoubleArray(0)
    private var preGain = 1.0

    fun reset() = state.fill(0.0)

    /** Filters `frames` interleaved frames in place. Returns false (and leaves them) when the equalizer is off. */
    fun process(samples: FloatArray, frames: Int, channels: Int, sampleRate: Int, eq: Equalizer.Snapshot): Boolean {
        if (!eq.enabled) return false
        if (eq.version != version || sampleRate != this.sampleRate || channels != this.channels) {
            coefficients = Array(Equalizer.frequencies.size) { b ->
                Equalizer.peaking(Equalizer.frequencies[b], eq.gains[b].toDouble(), sampleRate.toDouble())
            }
            if (channels != this.channels || sampleRate != this.sampleRate) state = DoubleArray(channels * coefficients.size * 2)
            preGain = 10.0.pow(-max(0f, eq.gains.maxOrNull() ?: 0f) / 20.0)
            version = eq.version
            this.sampleRate = sampleRate
            this.channels = channels
        }
        val sections = coefficients.size
        for (f in 0 until frames) {
            for (c in 0 until channels) {
                val i = f * channels + c
                var x = samples[i] * preGain
                var s = (c * sections) * 2
                for (b in 0 until sections) {
                    val k = coefficients[b]
                    val y = k[0] * x + state[s]
                    state[s] = k[1] * x - k[3] * y + state[s + 1]
                    state[s + 1] = k[2] * x - k[4] * y
                    x = y
                    s += 2
                }
                samples[i] = x.toFloat()
            }
        }
        return true
    }
}
