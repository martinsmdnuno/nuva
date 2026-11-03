package pt.nunomartins.nuva.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import pt.nunomartins.nuva.R

/** A skin's value for every token of docs/design-system/tokens.json. Skins change colours only. */
data class Palette(
    val surface0: Color, val surface1: Color, val surface2: Color,
    val display: Color, val displayInk: Color, val displayMuted: Color, val displayTrack: Color,
    val ink: Color, val inkMuted: Color, val line: Color,
    val keyFace: Color, val keyMode: Color, val keyPlay: Color, val keyInk: Color, val keyModeInk: Color,
    val track: Color, val fill: Color, val led: Color, val ledOff: Color, val signal: Color,
    val danger: Color, val focus: Color,
)

private fun c(hex: Long) = Color(0xFF000000 or hex)

/** The Mac app's skins. On a TV, Rams is its Lead theme: the room is dark and the display always is. */
enum class Skin(val id: String, val label: String, val palette: Palette, val fontSet: FontSet) {
    Rams(
        "rams", "Rams",
        Palette(
            c(0x1E2023), c(0x2B2D30), c(0x36393D), c(0x141517), c(0xE8E6E1), c(0x8E8C87), c(0x2E3033),
            c(0xE8E6E1), c(0xA6A49F), c(0x44474B), c(0xC9C6BF), c(0x6B6E73), c(0xE0A93E), c(0x1E2023), c(0xF8F7F4),
            c(0x44474B), c(0xC9C6BF), c(0xE0A93E), c(0x3A3D41), c(0xE0A93E), c(0xEE7A72), c(0x8FB4E3),
        ),
        FontSet.Inter,
    ),
    GraphiteOrange(
        "graphite-orange", "Graphite Orange",
        Palette(
            c(0x0B0F10), c(0x1C2427), c(0x382E22), c(0x050708), c(0xF2F4F5), c(0x9AA3A7), c(0x252C2F),
            c(0xF2F4F5), c(0x9AA3A7), c(0x2A3032), c(0xC9CED0), c(0x5B656C), c(0xFF6A00), c(0x0B0F10), c(0xF2F4F5),
            c(0x363E41), c(0xC9CED0), c(0xFF6A00), c(0x2A3032), c(0xFF6A00), c(0xFF6F8A), c(0x8FB4E3),
        ),
        FontSet.System,
    ),
    Phosphor(
        "phosphor", "Phosphor",
        Palette(
            c(0x1C1C2B), c(0x2C2C44), c(0x1B2A8F), c(0x000000), c(0x00E838), c(0x1FA83C), c(0x0E3A18),
            c(0xD8DCE6), c(0xA4A8BE), c(0x34344C), c(0xB6BACB), c(0x66668E), c(0x00D02A), c(0x10101C), c(0xF6F7FB),
            c(0x3E3E58), c(0xB6BACB), c(0x00D02A), c(0x34344C), c(0x00D02A), c(0xFF6B6B), c(0xF2C744),
        ),
        FontSet.Inter,
    ),
}

@OptIn(ExperimentalTextApi::class)
private fun variable(res: Int, vararg weights: FontWeight) =
    FontFamily(weights.map { Font(res, it, variationSettings = FontVariation.Settings(FontVariation.weight(it.weight))) })

/** The Mac app's font sets (View ▸ Font). Only the family changes; sizes and weights stay. */
enum class FontSet(val id: String, val label: String, val sans: FontFamily, val mono: FontFamily) {
    Inter(
        "inter", "Inter + IBM Plex Mono",
        variable(R.font.inter, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold),
        FontFamily(Font(R.font.plex_mono_light, FontWeight.Light), Font(R.font.plex_mono_regular), Font(R.font.plex_mono_medium, FontWeight.Medium)),
    ),
    /** The platform's own, as SF Pro + SF Mono are on the Mac: Roboto here. */
    System("system", "Roboto + Roboto Mono", FontFamily.SansSerif, FontFamily.Monospace),
    Plex(
        "plex", "IBM Plex Sans + Plex Mono",
        variable(R.font.plex_sans, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold),
        FontFamily(Font(R.font.plex_mono_light, FontWeight.Light), Font(R.font.plex_mono_regular), Font(R.font.plex_mono_medium, FontWeight.Medium)),
    ),
    Dm(
        "dm", "DM Sans + DM Mono",
        variable(R.font.dm_sans, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold),
        FontFamily(Font(R.font.dm_mono_light, FontWeight.Light), Font(R.font.dm_mono_regular), Font(R.font.dm_mono_medium, FontWeight.Medium)),
    ),
    /** One weight: light and medium fall to regular. */
    ShareTech("sharetech", "Share Tech + Share Tech Mono", FontFamily(Font(R.font.share_tech)), FontFamily(Font(R.font.share_tech_mono))),
}

/** The skin and font set in use, saved between launches. Reading them in a composable redraws it when they change. */
object Look {
    private var prefs: android.content.SharedPreferences? = null
    var skin by mutableStateOf(Skin.Rams)
        private set
    /** The set the user picked; null follows the skin. */
    var fontChoice by mutableStateOf<FontSet?>(null)
        private set
    val fontSet: FontSet get() = fontChoice ?: skin.fontSet

    fun init(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences("look", Context.MODE_PRIVATE)
        prefs = p
        skin = Skin.entries.firstOrNull { it.id == p.getString("skin", null) } ?: Skin.Rams
        fontChoice = FontSet.entries.firstOrNull { it.id == p.getString("fontSet", null) }
    }

    fun choose(skin: Skin) {
        this.skin = skin
        prefs?.edit()?.putString("skin", skin.id)?.apply()
    }

    fun choose(fonts: FontSet?) {
        fontChoice = fonts
        prefs?.edit()?.putString("fontSet", fonts?.id ?: "skin")?.apply()
    }
}

/** The current skin's tokens. */
object Tokens {
    private val p get() = Look.skin.palette
    val surface0 get() = p.surface0
    val surface1 get() = p.surface1
    val surface2 get() = p.surface2
    val display get() = p.display
    val displayInk get() = p.displayInk
    val displayMuted get() = p.displayMuted
    val displayTrack get() = p.displayTrack
    val ink get() = p.ink
    val inkMuted get() = p.inkMuted
    val line get() = p.line
    val keyFace get() = p.keyFace
    val keyMode get() = p.keyMode
    val keyPlay get() = p.keyPlay
    val keyInk get() = p.keyInk
    val keyModeInk get() = p.keyModeInk
    val track get() = p.track
    val fill get() = p.fill
    val led get() = p.led
    val ledOff get() = p.ledOff
    val signal get() = p.signal
    val danger get() = p.danger
    val focus get() = p.focus
}

/** The Mac's text styles at twice their size, for a screen across the room, in the current font set. */
object Type {
    private val sans get() = Look.fontSet.sans
    private val mono get() = Look.fontSet.mono
    val displayTime get() = TextStyle(fontFamily = mono, fontWeight = FontWeight.Light, fontSize = 50.sp, lineHeight = 56.sp)
    val displayMeta get() = TextStyle(fontFamily = mono, fontSize = 18.sp, lineHeight = 24.sp)
    val title get() = TextStyle(fontFamily = sans, fontWeight = FontWeight.Medium, fontSize = 26.sp, lineHeight = 32.sp)
    val body get() = TextStyle(fontFamily = sans, fontSize = 20.sp, lineHeight = 26.sp)
    val label get() = TextStyle(fontFamily = sans, fontWeight = FontWeight.Medium, fontSize = 18.sp, lineHeight = 22.sp)
    val legend get() = TextStyle(fontFamily = sans, fontSize = 15.sp, lineHeight = 18.sp, color = Tokens.inkMuted)
    val duration get() = TextStyle(fontFamily = mono, fontSize = 18.sp, lineHeight = 26.sp)
    val hint get() = TextStyle(fontFamily = mono, fontSize = 15.sp, lineHeight = 18.sp, color = Tokens.inkMuted)
}
