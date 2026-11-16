package pt.nunomartins.nuva.artwork

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.hypot
import pt.nunomartins.nuva.ui.Skin
import pt.nunomartins.nuva.ui.Temperaments

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
        motion.update(20.0, null).forEach { assertEquals(Temperaments.lead.idle.toFloat(), it.strength, 0.01f) }
        assertTrue("lights never hold still", path > 0.005)
    }

    @Test
    fun eachLightFollowsItsOwnPartOfTheSpectrum() {
        val motion = GlowMotion()
        var lights = motion.update(0.0, null)
        for (i in 1..60) lights = motion.update(i / 60.0, bands(bass = -12f, mid = -120f, treble = -120f))
        assertTrue(lights[0].strength > 0.95f)
        assertEquals(Temperaments.lead.idle.toFloat(), lights[1].strength, 0.01f)
        assertEquals(Temperaments.lead.idle.toFloat(), lights[2].strength, 0.01f)
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

    /** A kick of `ms` then silence for 300 ms: the bass light's peak and what is left of it. */
    private fun kick(motion: GlowMotion, ms: Int): Pair<Float, Float> {
        var t = 0.0
        var peak = 0f
        repeat(ms * 60 / 1000) { t += 1 / 60.0; peak = motion.update(t, bands(-12f, -60f, -60f))[0].strength }
        var after = 0f
        repeat(18) { t += 1 / 60.0; after = motion.update(t, null)[0].strength }
        return peak to after
    }

    @Test
    fun raveFlaresAndFallsVelvetTakesItsTime() {
        val rave = kick(GlowMotion(Temperaments.rave), 50)
        val rams = kick(GlowMotion(Temperaments.lead), 50)
        val velvet = kick(GlowMotion(Temperaments.velvet), 50)
        assertTrue("rave ${rave.first} rams ${rams.first}", rave.first > rams.first)
        assertTrue("rams ${rams.first} velvet ${velvet.first}", rams.first > velvet.first)
        assertTrue("rave falls back: ${rave.second} vs ${rams.second}", rave.second < rams.second)
        // Between beats Rave is darker than Rams, so each beat stands out.
        assertTrue(Temperaments.rave.idle < Temperaments.lead.idle)
    }

    @Test
    fun raveTravelsFasterThanVelvet() {
        val loud = bands(-12f, -18f, -24f)
        assertTrue(travel(GlowMotion(Temperaments.rave), 20.0, loud) > travel(GlowMotion(Temperaments.velvet), 20.0, loud) * 3)
    }

    @Test
    fun everySkinHasAWholeTemperament() {
        for (skin in Skin.entries) {
            val g = skin.glow
            assertTrue(skin.id, g.attack.size == 3 && g.release.size == 3 && (g.lights?.size ?: 3) == 3)
            assertTrue(skin.id, g.breath in 0.0..1.0 && g.idle in 0.0..1.0 && g.speed > 0)
        }
    }
}
