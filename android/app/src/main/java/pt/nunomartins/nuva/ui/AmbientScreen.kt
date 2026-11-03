package pt.nunomartins.nuva.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.R
import kotlin.math.sin

/**
 * The Display face at the scale of the room: the screen is all display. Sizes come from the
 * screen's width, as the Mac's `ambient-*` styles do. OLED protection: the content takes 84% of
 * the screen and wanders slowly over the rest; the position bar, which barely changes, sits at 55%.
 */
@Composable
fun AmbientScreen(model: AppModel) {
    val state by model.player.state.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }
    // A slow path that doesn't repeat for days: two sines with periods that share no factor.
    val t = now / 1000.0
    val dx = (sin(t / 631) * 0.6 + sin(t / 197) * 0.4).toFloat()
    val dy = (sin(t / 541 + 1.3) * 0.6 + sin(t / 173 + 0.7) * 0.4).toFloat()

    BoxWithConstraints(Modifier.fillMaxSize().background(Tokens.display)) {
        val vw = maxWidth / 100
        val current = state.current
        Box(
            Modifier
                .fillMaxSize(0.84f)
                .align(Alignment.Center)
                .offset(x = maxWidth * 0.08f * dx, y = maxHeight * 0.08f * dy),
        ) {
            Row(Modifier.fillMaxWidth().align(Alignment.TopStart), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(vw)) {
                Led(state.isPlaying, size = vw * 0.8f)
                Text(state.formatLabel.ifEmpty { current?.format.orEmpty() }, Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = (vw * 1.7f).toSp()))
            }
            Column(Modifier.fillMaxWidth().align(Alignment.BottomStart)) {
                Text(
                    current?.title ?: stringResource(R.string.nothing_playing),
                    Type.title.copy(color = Tokens.displayInk, fontSize = (vw * 5.6f).toSp(), lineHeight = (vw * 6.6f).toSp()),
                )
                Text(current?.folderName.orEmpty(), Type.body.copy(color = Tokens.displayMuted, fontSize = (vw * 2.3f).toSp(), lineHeight = (vw * 3f).toSp()))
                Spacer(Modifier.height(vw * 2))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Text(clock(state.position), Type.displayTime.copy(color = Tokens.displayInk, fontSize = (vw * 13f).toSp(), lineHeight = (vw * 14f).toSp()), Modifier.weight(1f))
                    Text(clock(state.duration), Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = (vw * 2.2f).toSp()))
                }
                Spacer(Modifier.height(vw * 1.5f))
                PositionBar(
                    if (state.duration > 0) (state.position / state.duration).toFloat() else 0f,
                    Modifier.alpha(0.55f), height = vw * 0.35f,
                )
            }
        }
    }
}

@Composable
private fun androidx.compose.ui.unit.Dp.toSp() = with(androidx.compose.ui.platform.LocalDensity.current) { this@toSp.toSp() }
