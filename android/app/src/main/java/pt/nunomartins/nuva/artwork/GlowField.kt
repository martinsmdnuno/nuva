package pt.nunomartins.nuva.artwork

import kotlin.math.floor
import kotlin.math.sqrt

/**
 * Ambient mode's glow, before it becomes pixels: the cover's 4×4 grid of shaded colours and the
 * display's colour. It is drawn at the screen's own size, one screen pixel per pixel, so a 4K
 * screen gets no blocks from a small image stretched over it:
 * - a cubic B-spline between the cells (smooth to the second derivative, no creases, and every
 *   pixel a weighted mean of the cells, so no colour goes past the contrast the cells were shaded to);
 * - a smoothstep vignette towards the display's colour at the edges;
 * - triangular dither of ±1 level before rounding to 8 bits, so the slow, dark gradients show no bands.
 * Plain Kotlin (colours as ARGB ints), so it is tested without Android.
 */
class GlowField(val cells: IntArray, val display: Int) {
    init {
        require(cells.size == GRID * GRID)
    }

    /**
     * Renders the field at `width`×`height`, one row at a time (ARGB, opaque) into `sink`. `dim` below 1
     * moves it towards the display's colour, leaving room for the lights to bring the contrast back.
     */
    fun render(width: Int, height: Int, dim: Float = 1f, sink: (y: Int, row: IntArray) -> Unit) {
        val columns = columns(width)
        val exact = FloatArray(width * 3)
        val row = IntArray(width)
        for (y in 0 until height) {
            exactRow(y, width, height, columns, exact, dim)
            for (x in 0 until width) {
                val noise = hash(x * 7919 + y * 104_729 + seed)
                val noise2 = hash(noise)
                val r = dither(exact[x * 3], noise and 0xFFFF, noise ushr 16)
                val g = dither(exact[x * 3 + 1], noise2 and 0xFFFF, noise2 ushr 16)
                val b = dither(exact[x * 3 + 2], (noise xor noise2) and 0xFFFF, (noise + noise2) ushr 16)
                row[x] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
            sink(y, row)
        }
    }

    /**
     * The colours of the moving lights: the cover's brightest cell, then the cells most unlike the ones
     * already chosen (among the brighter half), so the lights carry the cover's range, not one colour.
     */
    fun lightColours(count: Int = 3): IntArray {
        val bright = cells.sortedByDescending { luminance(it) }.take(GRID * GRID / 2)
        val chosen = mutableListOf(bright.first())
        while (chosen.size < count) chosen += bright.maxBy { c -> chosen.minOf { distance(it, c) } }
        return chosen.toIntArray()
    }

    /** Each grid row interpolated across the width: [gridRow][x][rgb], 0–255 as floats. */
    internal fun columns(width: Int): FloatArray {
        val out = FloatArray(GRID * width * 3)
        val weights = FloatArray(4)
        for (x in 0 until width) {
            val gx = (x + 0.5f) / width * GRID - 0.5f
            val base = spline(gx, weights)
            for (gridRow in 0 until GRID) {
                var r = 0f; var g = 0f; var b = 0f
                for (k in 0 until 4) {
                    val cell = cells[gridRow * GRID + (base + k).coerceIn(0, GRID - 1)]
                    r += weights[k] * red(cell); g += weights[k] * green(cell); b += weights[k] * blue(cell)
                }
                val i = (gridRow * width + x) * 3
                out[i] = r; out[i + 1] = g; out[i + 2] = b
            }
        }
        return out
    }

    /** Row `y` before rounding: the spline down the grid rows, then the vignette. */
    internal fun exactRow(y: Int, width: Int, height: Int, columns: FloatArray, out: FloatArray, dim: Float = 1f) {
        val weights = FloatArray(4)
        val gy = (y + 0.5f) / height * GRID - 0.5f
        val base = spline(gy, weights)
        val rows = IntArray(4) { (base + it).coerceIn(0, GRID - 1) }
        val dr = red(display).toFloat(); val dg = green(display).toFloat(); val db = blue(display).toFloat()
        val dy = ((y + 0.5f) / height - 0.5f) * height / width
        for (x in 0 until width) {
            var r = 0f; var g = 0f; var b = 0f
            for (k in 0 until 4) {
                val i = (rows[k] * width + x) * 3
                r += weights[k] * columns[i]; g += weights[k] * columns[i + 1]; b += weights[k] * columns[i + 2]
            }
            val dx = (x + 0.5f) / width - 0.5f
            val edge = 1 - (1 - smoothstep(0.22f, 0.62f, sqrt(dx * dx + dy * dy)) * 0.55f) * dim
            out[x * 3] = r + (dr - r) * edge
            out[x * 3 + 1] = g + (dg - g) * edge
            out[x * 3 + 2] = b + (db - b) * edge
        }
    }

    companion object {
        const val GRID = 4

        /**
         * A soft round light of `colour`, `size`×`size`, as premultiplied ARGB: full at the centre, falling
         * as (1 − r²)³ to nothing at the edge, with the same dither on every channel and on alpha.
         */
        fun renderLight(colour: Int, size: Int, sink: (y: Int, row: IntArray) -> Unit) {
            val row = IntArray(size)
            val half = size / 2f
            val cr = red(colour).toFloat(); val cg = green(colour).toFloat(); val cb = blue(colour).toFloat()
            for (y in 0 until size) {
                for (x in 0 until size) {
                    val dx = (x + 0.5f - half) / half
                    val dy = (y + 0.5f - half) / half
                    val q = (1 - (dx * dx + dy * dy)).coerceAtLeast(0f)
                    val m = q * q * q
                    val noise = hash(x * 7919 + y * 104_729 + seed + 1)
                    val noise2 = hash(noise)
                    val a = dither(m * 255, noise and 0xFFFF, noise ushr 16)
                    val r = minOf(a, dither(cr * m, noise2 and 0xFFFF, noise2 ushr 16))
                    val g = minOf(a, dither(cg * m, (noise xor noise2) and 0xFFFF, (noise + noise2) ushr 16))
                    val b = minOf(a, dither(cb * m, (noise2 * 31) and 0xFFFF, (noise * 17) ushr 16))
                    row[x] = (a shl 24) or (r shl 16) or (g shl 8) or b
                }
                sink(y, row)
            }
        }

        /** WCAG relative luminance of an ARGB colour. */
        fun luminance(c: Int): Double {
            fun linear(v: Int): Double {
                val x = v / 255.0
                return if (x <= 0.04045) x / 12.92 else Math.pow((x + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red(c)) + 0.7152 * linear(green(c)) + 0.0722 * linear(blue(c))
        }

        private fun distance(a: Int, b: Int): Int {
            val dr = red(a) - red(b); val dg = green(a) - green(b); val db = blue(a) - blue(b)
            return dr * dr + dg * dg + db * db
        }
        private const val seed = 0x5EED

        /** Uniform cubic B-spline weights at `t` (in cells) for cells base…base+3; returns base. */
        private fun spline(t: Float, w: FloatArray): Int {
            val i = floor(t).toInt()
            val f = t - i
            val f2 = f * f
            val f3 = f2 * f
            w[0] = (1 - f) * (1 - f) * (1 - f) / 6
            w[1] = (3 * f3 - 6 * f2 + 4) / 6
            w[2] = (-3 * f3 + 3 * f2 + 3 * f + 1) / 6
            w[3] = f3 / 6
            return i - 1
        }

        private fun smoothstep(from: Float, to: Float, v: Float): Float {
            val t = ((v - from) / (to - from)).coerceIn(0f, 1f)
            return t * t * (3 - 2 * t)
        }

        /** Rounds `v` after adding triangular noise in (−1, 1) made from two 16-bit uniforms. */
        private fun dither(v: Float, a: Int, b: Int): Int =
            (v + (a + b) / 65_536f - 1f + 0.5f).toInt().coerceIn(0, 255)

        /** A small integer hash (lowbias32): noise without a visible pattern, the same every frame. */
        private fun hash(seed: Int): Int {
            var h = seed
            h = h xor (h ushr 16); h *= 0x7feb352d
            h = h xor (h ushr 15); h *= -0x7b935975
            return h xor (h ushr 16)
        }

        private fun red(c: Int) = (c shr 16) and 0xFF
        private fun green(c: Int) = (c shr 8) and 0xFF
        private fun blue(c: Int) = c and 0xFF
    }
}
