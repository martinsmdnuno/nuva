package pt.nunomartins.nuva.audio

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Levels of the equalizer's 10 bands, the ambient face's 28 fine bands, and left and right, measured
 * after the equalizer so the meters show what is heard. Each measurement carries its time on the
 * audio output's clock: the processor runs ahead of the speakers, and the display asks for the
 * moment being played. A port of the Mac app's `Spectrum.swift`.
 */
class SpectrumShared {
    companion object {
        const val BANDS = 10
        const val FINE_BANDS = 28
        /** 28 bands evenly spaced in log frequency from 20 Hz to 20 kHz. */
        val fineCentres = DoubleArray(FINE_BANDS) { i -> 20 * 1000.0.pow((i + 0.5) / FINE_BANDS) }
        /** About 4 s of measurements at 120 a second, more than the output's buffer. */
        const val CAPACITY = 512
    }

    private val times = DoubleArray(CAPACITY) { -1.0 }
    private val levels = FloatArray(CAPACITY * BANDS)
    private val fine = FloatArray(CAPACITY * FINE_BANDS) { -120f }
    /** Per measurement: RMS left, RMS right, peak left, peak right, in dBFS. */
    private val stereo = FloatArray(CAPACITY * 4) { -120f }
    private var next = 0
    private var watchers = 0
    private val lock = Any()

    /** Meters on screen. With none, nothing is measured. */
    val isWatched: Boolean get() = synchronized(lock) { watchers > 0 }

    fun watch(on: Boolean) = synchronized(lock) { watchers = max(0, watchers + if (on) 1 else -1) }

    /** Forgets everything: a seek or a new track. */
    fun clear() = synchronized(lock) { times.fill(-1.0) }

    /** Audio thread. `levels`: dBFS per band; `stereo`: RMS L, RMS R, peak L, peak R. */
    fun write(time: Double, levels: FloatArray, fine: FloatArray, stereo: FloatArray) = synchronized(lock) {
        val i = next
        times[i] = time
        System.arraycopy(levels, 0, this.levels, i * BANDS, BANDS)
        System.arraycopy(fine, 0, this.fine, i * FINE_BANDS, FINE_BANDS)
        System.arraycopy(stereo, 0, this.stereo, i * 4, 4)
        next = (i + 1) % CAPACITY
    }

    /** Band levels at `time`, between the measurements either side, or null when none is close (paused, seeking). */
    fun levels(time: Double, tolerance: Double = 0.15): FloatArray? = read(levels, BANDS, time, tolerance)

    fun fineLevels(time: Double, tolerance: Double = 0.15): FloatArray? = read(fine, FINE_BANDS, time, tolerance)

    /** RMS L, RMS R, peak L, peak R in dBFS at `time`. */
    fun stereo(time: Double, tolerance: Double = 0.15): FloatArray? = read(stereo, 4, time, tolerance)

    private fun read(values: FloatArray, width: Int, time: Double, tolerance: Double): FloatArray? = synchronized(lock) {
        var before = -1
        var after = -1
        var early = Double.NEGATIVE_INFINITY
        var late = Double.POSITIVE_INFINITY
        for (i in 0 until CAPACITY) {
            val t = times[i]
            if (t < 0 || abs(t - time) > tolerance) continue
            if (t <= time && t > early) { before = i; early = t }
            if (t >= time && t < late) { after = i; late = t }
        }
        if (before < 0 && after < 0) return null
        if (before < 0) before = after
        if (after < 0) after = before
        val weight = if (late > early && late.isFinite() && early.isFinite()) ((time - early) / (late - early)).toFloat() else 0f
        FloatArray(width) { k ->
            val x = values[before * width + k]
            x + (values[after * width + k] - x) * weight
        }
    }
}

/**
 * Keeps the last samples in mono and, 120 times a second, sums FFT power into the equalizer's octave
 * bands and the 28 fine bands, with the left and right levels of the same moment. Two transforms: a
 * short one (about 43 ms) for the mids and treble, and one four times longer for the bass, where a
 * short window can't tell 25 Hz from 40 Hz. Both are centred on the moment the measurement carries.
 */
class SpectrumAnalyzer(private val sampleRate: Int) {
    companion object {
        const val RATE = 120.0
        const val CROSSOVER = 400.0
    }

    private val shortSize = if (sampleRate <= 48_000) 2048 else if (sampleRate <= 96_000) 4096 else 8192
    private val short = Transform(shortSize, sampleRate)
    private val long = Transform(shortSize * 4, sampleRate)
    private val hop = max(1, (sampleRate / RATE).toInt())
    private val bandBins = Equalizer.frequencies.map { f ->
        val t = if (f < CROSSOVER) long else short
        (f < CROSSOVER) to t.bins(f / sqrt(2.0), f * sqrt(2.0))
    }
    private val fineBins = SpectrumShared.fineCentres.map { f ->
        val ratio = 1000.0.pow(0.5 / SpectrumShared.FINE_BANDS)
        val t = if (f < CROSSOVER) long else short
        (f < CROSSOVER) to t.bins(f / ratio, f * ratio)
    }
    private val history = FloatArray(long.size)
    private var head = 0
    private var pending = 0
    private val levels = FloatArray(SpectrumShared.BANDS)
    private val fine = FloatArray(SpectrumShared.FINE_BANDS)
    private var sumL = 0.0
    private var sumR = 0.0
    private var highL = 0f
    private var highR = 0f
    private var counted = 0
    /** The last hops' left and right levels, so a measurement carries those of its own moment. */
    private val recent = Array(((long.size / 2.0) / hop).toInt() + 1) { FloatArray(4) { -120f } }
    private var recentHead = 0
    private val stereoOut = FloatArray(4)

    /**
     * Adds `frames` interleaved frames (floats, -1…1) and measures every 1/120 s of them. `end` is the
     * output clock's time, in seconds, at the end of the block.
     */
    fun process(samples: FloatArray, channels: Int, frames: Int, end: Double, shared: SpectrumShared) {
        var f = 0
        while (f < frames) {
            val base = f * channels
            val l = samples[base]
            val r = if (channels > 1) samples[base + 1] else l
            sumL += (l * l).toDouble()
            sumR += (r * r).toDouble()
            highL = max(highL, abs(l))
            highR = max(highR, abs(r))
            counted++
            history[head] = (l + r) * 0.5f
            head = (head + 1) % history.size
            f++
            pending++
            if (pending < hop) continue
            pending = 0
            val slot = recent[recentHead]
            slot[0] = decibels(sqrt(sumL / max(counted, 1)).toFloat())
            slot[1] = decibels(sqrt(sumR / max(counted, 1)).toFloat())
            slot[2] = decibels(highL)
            slot[3] = decibels(highR)
            recentHead = (recentHead + 1) % recent.size
            sumL = 0.0; sumR = 0.0; highL = 0f; highR = 0f; counted = 0
            measure()
            // Centred half a long window back; `recentHead` is now the oldest hop kept, from then.
            val time = end - (frames - f).toDouble() / sampleRate - (long.size / 2).toDouble() / sampleRate
            System.arraycopy(recent[recentHead], 0, stereoOut, 0, 4)
            shared.write(time, levels, fine, stereoOut)
        }
    }

    private fun measure() {
        long.run(history, head)
        short.run(history, (head - long.size / 2 + short.size / 2 + history.size) % history.size)
        for ((b, band) in bandBins.withIndex()) levels[b] = (if (band.first) long else short).level(band.second)
        for ((b, band) in fineBins.withIndex()) fine[b] = (if (band.first) long else short).level(band.second)
    }

    private fun decibels(amplitude: Float) = 20 * log10(max(amplitude, 1e-6f))
}

/** One FFT size, with its Hann window and buffers. */
internal class Transform(val size: Int, sampleRate: Int) {
    private val window = FloatArray(size) { i -> (0.5 - 0.5 * cos(2 * PI * i / size)).toFloat() }
    private val binWidth = sampleRate.toDouble() / size
    /** Power of a full-scale sine summed over its bins, with this window: (N/2)² · mean(w²) · 2 / 2. */
    private val fullScale = (0.375 * size * size / 4).toFloat()
    private val real = FloatArray(size)
    private val imag = FloatArray(size)
    private val power = FloatArray(size / 2)
    private val bits = (ln(size.toDouble()) / ln(2.0)).toInt()
    private val cosTable = FloatArray(size / 2) { cos(2 * PI * it / size).toFloat() }
    private val sinTable = FloatArray(size / 2) { sin(2 * PI * it / size).toFloat() }

    /** The bins covering `low` to `high` Hz, at least one (bin 0 is DC: never used). */
    fun bins(low: Double, high: Double): IntRange {
        val lo = max(1, (low / binWidth).toInt())
        val hi = min(size / 2, max(lo + 1, kotlin.math.ceil(high / binWidth).toInt()))
        return lo until hi
    }

    /** Power spectrum of the `size` samples of the ring `history` that end just before `end`. */
    fun run(history: FloatArray, end: Int) {
        val start = (end - size + history.size) % history.size
        for (i in 0 until size) {
            val j = reverse(i)
            real[j] = history[(start + i) % history.size] * window[i]
            imag[j] = 0f
        }
        var len = 2
        while (len <= size) {
            val half = len / 2
            val step = size / len
            var i = 0
            while (i < size) {
                for (k in 0 until half) {
                    val c = cosTable[k * step]
                    val s = -sinTable[k * step]
                    val a = i + k
                    val b = a + half
                    val tr = real[b] * c - imag[b] * s
                    val ti = real[b] * s + imag[b] * c
                    real[b] = real[a] - tr
                    imag[b] = imag[a] - ti
                    real[a] += tr
                    imag[a] += ti
                }
                i += len
            }
            len *= 2
        }
        for (k in 0 until size / 2) power[k] = real[k] * real[k] + imag[k] * imag[k]
    }

    /** dBFS of the last run's power over `bins`. */
    fun level(bins: IntRange): Float {
        var sum = 0f
        for (k in bins) sum += power[k]
        return 10 * log10(max(sum / fullScale, 1e-12f))
    }

    private fun reverse(x: Int): Int {
        var v = x
        var r = 0
        repeat(bits) { r = (r shl 1) or (v and 1); v = v shr 1 }
        return r
    }
}
