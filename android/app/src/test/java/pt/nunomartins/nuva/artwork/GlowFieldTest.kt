package pt.nunomartins.nuva.artwork

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class GlowFieldTest {
    private fun rgb(r: Int, g: Int, b: Int) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    /** A dark purple field, brighter on the right: the kind of slow gradient that banded. */
    private val field = GlowField(
        IntArray(16) { i -> val column = i % 4; rgb(30 + column * 6, 10 + column * 2, 60 + column * 10) },
        display = rgb(24, 8, 48),
    )

    private fun render(w: Int, h: Int): List<IntArray> {
        val rows = mutableListOf<IntArray>()
        field.render(w, h) { _, row -> rows += row.copyOf() }
        return rows
    }

    private fun exact(w: Int, h: Int, y: Int): FloatArray {
        val out = FloatArray(w * 3)
        field.exactRow(y, w, h, field.columns(w), out)
        return out
    }

    @Test
    fun everyPixelIsWithinOneAndAHalfLevelsOfTheExactColour() {
        val w = 384; val h = 216
        val rows = render(w, h)
        for (y in 0 until h step 7) {
            val e = exact(w, h, y)
            for (x in 0 until w) {
                val p = rows[y][x]
                assertTrue(abs(((p shr 16) and 0xFF) - e[x * 3]) < 1.5f)
                assertTrue(abs(((p shr 8) and 0xFF) - e[x * 3 + 1]) < 1.5f)
                assertTrue(abs((p and 0xFF) - e[x * 3 + 2]) < 1.5f)
            }
        }
    }

    /** Dither keeps the levels between 8-bit steps: a block's mean follows the exact colour, not a band. */
    @Test
    fun blocksAverageToTheExactColour() {
        val w = 512; val h = 256
        val rows = render(w, h)
        for (bx in 0 until w step 64) {
            var sum = 0.0; var exactSum = 0.0
            for (y in 100 until 132) {
                val e = exact(w, h, y)
                for (x in bx until bx + 32) {
                    sum += rows[y][x] and 0xFF
                    exactSum += e[x * 3 + 2]
                }
            }
            assertEquals(exactSum / 1024, sum / 1024, 0.15)
        }
    }

    @Test
    fun opaqueAndNeverPastTheBrightestCell() {
        val rows = render(320, 180)
        val brightestBlue = 60 + 3 * 10
        for (row in rows) for (p in row) {
            assertEquals(0xFF, p ushr 24)
            assertTrue((p and 0xFF) <= brightestBlue + 1)
        }
    }

    @Test
    fun lightsAreValidPremultipliedAndNeverBrighterThanTheirColour() {
        val colour = field.lightColours()[0]
        var centre = 0
        GlowField.renderLight(colour, 200) { y, row ->
            for (p in row) {
                val a = p ushr 24
                assertTrue(((p shr 16) and 0xFF) <= a && ((p shr 8) and 0xFF) <= a && (p and 0xFF) <= a)
                assertTrue((p and 0xFF) <= (colour and 0xFF) + 1)
            }
            if (y == 100) centre = row[100] ushr 24
        }
        assertTrue(centre > 250)
    }

    @Test
    fun lightColoursStartWithTheBrightestAndDiffer() {
        val colours = field.lightColours()
        assertEquals(3, colours.size)
        assertEquals(field.cells.maxBy { GlowField.luminance(it) }, colours[0])
        assertTrue(colours[1] != colours[0])
    }
}
