package pt.nunomartins.nuva.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import pt.nunomartins.nuva.R

/** The design system's tokens (docs/design-system/tokens.json), in Lead: a TV room is dark. */
object Tokens {
    val surface0 = Color(0xFF1E2023)
    val surface1 = Color(0xFF2B2D30)
    val surface2 = Color(0xFF36393D)
    val display = Color(0xFF141517)
    val displayInk = Color(0xFFE8E6E1)
    val displayMuted = Color(0xFF8E8C87)
    val displayTrack = Color(0xFF2E3033)
    val ink = Color(0xFFE8E6E1)
    val inkMuted = Color(0xFFA6A49F)
    val line = Color(0xFF44474B)
    val keyFace = Color(0xFFC9C6BF)
    val keyMode = Color(0xFF6B6E73)
    val keyPlay = Color(0xFFE0A93E)
    val keyInk = Color(0xFF1E2023)
    val keyModeInk = Color(0xFFF8F7F4)
    val led = Color(0xFFE0A93E)
    val ledOff = Color(0xFF3A3D41)
    val signal = Color(0xFFE0A93E)
    val danger = Color(0xFFEE7A72)
    val focus = Color(0xFF8FB4E3)
}

@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
private fun inter(weight: FontWeight) =
    Font(R.font.inter, weight, variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)))

val Inter = FontFamily(inter(FontWeight.Normal), inter(FontWeight.Medium), inter(FontWeight.SemiBold))
val PlexMono = FontFamily(
    Font(R.font.plex_mono_light, FontWeight.Light),
    Font(R.font.plex_mono_regular, FontWeight.Normal),
    Font(R.font.plex_mono_medium, FontWeight.Medium),
)

/** The Mac's text styles at twice their size, for a screen across the room. */
object Type {
    val displayTime = TextStyle(fontFamily = PlexMono, fontWeight = FontWeight.Light, fontSize = 56.sp, lineHeight = 64.sp)
    val displayMeta = TextStyle(fontFamily = PlexMono, fontSize = 18.sp, lineHeight = 24.sp)
    val title = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 26.sp, lineHeight = 32.sp)
    val body = TextStyle(fontFamily = Inter, fontSize = 20.sp, lineHeight = 26.sp)
    val label = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 18.sp, lineHeight = 22.sp)
    val legend = TextStyle(fontFamily = Inter, fontSize = 15.sp, lineHeight = 18.sp, color = Tokens.inkMuted)
    val duration = TextStyle(fontFamily = PlexMono, fontSize = 18.sp, lineHeight = 26.sp)
}
