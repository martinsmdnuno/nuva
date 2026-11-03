package pt.nunomartins.nuva.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

class AudioTest {
    /** A stereo sine through the analyzer; returns what was written last. */
    private fun measure(frequency: Double, amplitude: Float, rate: Int, right: Float = amplitude): SpectrumShared {
        val analyzer = SpectrumAnalyzer(rate)
        val shared = SpectrumShared()
        val frames = 1024
        val block = FloatArray(frames * 2)
        var n = 0
        repeat(40) {
            for (j in 0 until frames) {
                val v = sin(2 * PI * frequency * (n + j) / rate).toFloat()
                block[2 * j] = amplitude * v
                block[2 * j + 1] = right * v
            }
            n += frames
            analyzer.process(block, 2, frames, n.toDouble() / rate, shared)
        }
        return shared
    }

    @Test fun fullScaleSineReadsZeroInItsBand() {
        for (rate in listOf(44_100, 96_000, 192_000)) {
            val shared = measure(1000.0, 1f, rate)
            val levels = shared.levels(40 * 1024.0 / rate, tolerance = 1.0)!!
            assertTrue("rate $rate: ${levels[5]}", abs(levels[5]) < 1.5f)
            for (b in listOf(0, 1, 2, 8, 9)) assertTrue("rate $rate band $b: ${levels[b]}", levels[b] < -40f)
        }
    }

    @Test fun stereoLevelsAreRmsAndPeak() {
        val shared = measure(1000.0, 0.1f, 48_000, right = 0f)
        val stereo = shared.stereo(40 * 1024.0 / 48_000, tolerance = 1.0)!!
        assertEquals(-23f, stereo[0], 0.5f)
        assertEquals(-20f, stereo[2], 0.5f)
        assertTrue(stereo[1] < -100f)
    }

    @Test fun bassBandsAreToldApart() {
        val shared = measure(40.0, 0.5f, 48_000)
        val fine = shared.fineLevels(40 * 1024.0 / 48_000, tolerance = 1.0)!!
        val loudest = fine.indices.maxBy { fine[it] }
        val centre = SpectrumShared.fineCentres[loudest]
        assertTrue("centre $centre", centre > 32 && centre < 50)
        assertTrue(fine[0] < fine[loudest] - 10)
    }

    @Test fun lookupBlendsTheMeasurementsAroundTheTime() {
        val shared = SpectrumShared()
        shared.write(10.0, FloatArray(10) { -10f }, FloatArray(28), floatArrayOf(-10f, -10f, -10f, -10f))
        shared.write(10.1, FloatArray(10) { -30f }, FloatArray(28), floatArrayOf(-30f, -30f, -30f, -30f))
        assertEquals(-20f, shared.levels(10.05)!![0], 0.01f)
        assertEquals(null, shared.levels(11.0))
    }

    @Test fun equalizerBoostsItsBandAndKeepsHeadroom() {
        val rate = 48_000
        val gains = FloatArray(10).also { it[5] = 12f }
        val filter = EqFilter()
        val frames = 48_000
        val samples = FloatArray(frames) { sin(2 * PI * 1000 * it / rate).toFloat() * 0.25f }
        filter.process(samples, frames, 1, rate, Equalizer.Snapshot(gains, true, 1))
        val peak = samples.drop(frames / 2).maxOf { abs(it) }
        // +12 dB at 1 kHz with -12 dB of pre-gain: the 1 kHz tone comes out at the same level.
        assertEquals(0.25f, peak, 0.02f)
        val off = FloatArray(4) { 0.5f }
        assertTrue(!EqFilter().process(off, 4, 1, rate, Equalizer.Snapshot(FloatArray(10), false, 1)))
        assertEquals(0.5f, off[0])
    }
}
