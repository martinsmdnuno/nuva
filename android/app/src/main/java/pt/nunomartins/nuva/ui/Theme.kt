package pt.nunomartins.nuva.ui

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import pt.nunomartins.nuva.R

/** The Mac app's skins. On a TV, Rams is its Lead theme: the room is dark and the display always is. */
enum class Skin(val id: String, val label: String, val palette: Palette, val fontSet: FontSet) {
    Rams(
        "rams", "Rams",
        Palettes.lead,
        FontSet.Inter,
    ),
    GraphiteOrange(
        "graphite-orange", "Graphite Orange",
        Palettes.graphiteOrange,
        FontSet.System,
    ),
    Phosphor(
        "phosphor", "Phosphor",
        Palettes.phosphor,
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
