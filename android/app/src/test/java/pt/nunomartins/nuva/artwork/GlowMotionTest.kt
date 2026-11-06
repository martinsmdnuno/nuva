package pt.nunomartins.nuva.artwork

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.hypot

class GlowMotionTest {
    private fun bands(bass: Float, mid: Float, treble: Float) =
        FloatArray(10) { i -> if (i <= 2) bass else if (i <= 6) mid else treble }

    /** How far the first light travels in `seconds` at 60 frames a second. */
    private fun travel(motion: GlowMotion, seconds: Double, input: FloatArray?): Double {
        var t = 0.0
        var path = 0.0
        var last = motion.update(t, input)[0]
        while (t < seconds) {
            t += 1 / 60.0
            val now = motion.update(t, input)[0]
            path += hypot((now.x - last.x).toDouble(), (now.y - last.y).toDouble())
            last = now
        }
        return path
    }

    @Test
    fun silentLightsRestAtIdleStrengthAndStillMove() {
        val motion = GlowMotion()
        val path = travel(motion, 20.0, null)
        motion.update(20.0, null).forEach { assertEquals(GlowMotion.IDLE.toFloat(), it.strength, 0.01f) }
        assertTrue("lights never hold still", path > 0.005)
    }

    @Test
    fun eachLightFollowsItsOwnPartOfTheSpectrum() {
        val motion = GlowMotion()
        var lights = motion.update(0.0, null)
        for (i in 1..60) lights = motion.update(i / 60.0, bands(bass = -12f, mid = -120f, treble = -120f))
        assertTrue(lights[0].strength > 0.95f)
        assertEquals(GlowMotion.IDLE.toFloat(), lights[1].strength, 0.01f)
        assertEquals(GlowMotion.IDLE.toFloat(), lights[2].strength, 0.01f)
    }

    @Test
    fun loudMusicMovesTheLightsFaster() {
        val quiet = travel(GlowMotion(), 20.0, null)
        val loud = travel(GlowMotion(), 20.0, bands(-12f, -18f, -24f))
        assertTrue("loud $loud vs quiet $quiet", loud > quiet * 4)
    }

    @Test
    fun lightsStayOnTheScreen() {
        val motion = GlowMotion()
        for (i in 0..36_000) motion.update(i / 10.0, bands(-12f, -18f, -24f)).forEach {
            assertTrue(it.x in 0.15f..0.85f && it.y in 0.2f..0.8f)
        }
    }
}
