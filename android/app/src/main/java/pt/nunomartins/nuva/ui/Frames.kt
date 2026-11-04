package pt.nunomartins.nuva.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.MarqueeAnimationMode
import androidx.compose.foundation.MarqueeSpacing
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.basicMarquee
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.BasicText
import kotlinx.coroutines.delay
import pt.nunomartins.nuva.audio.Audio

/**
 * The screen's frames while music plays (at the display's own rate, 120 Hz on a TV that has it), and
 * for 2 s after a pause so meters fall instead of freezing. Returns the frame time in seconds; reading
 * it redraws the caller every frame. Also tells the audio thread a meter is on screen.
 */
@Composable
fun meterFrames(playing: Boolean): Double {
    var nanos by remember { mutableLongStateOf(System.nanoTime()) }
    var settling by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        Audio.spectrum.watch(true)
        onDispose { Audio.spectrum.watch(false) }
    }
    LaunchedEffect(playing) {
        if (!playing) {
            settling = true
            delay(2000)
            settling = false
        }
    }
    LaunchedEffect(playing, settling) {
        while (playing || settling) withFrameNanos { nanos = it }
    }
    return nanos / 1e9
}

/**
 * Text that slides when it doesn't fit, so long names can be read whole: always, or only with focus.
 * At rest a name that doesn't fit ends with an ellipsis. Sliding, it pauses at the start of each
 * pass, and its ends fade over `fade` drawn just outside its box, so the text still lines up with
 * the text above and below it and never stops short at a hard edge.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ScrollingText(text: String, style: TextStyle, modifier: Modifier = Modifier, moving: Boolean = true, fade: Dp = 10.dp) {
    if (!moving) {
        Text(text, style, modifier)
        return
    }
    BasicText(
        text,
        modifier
            .layout { measurable, constraints ->
                // Wider by the fades on both sides, placed back by one: the fades fall outside the box.
                val edge = fade.roundToPx()
                val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + edge * 2 else constraints.maxWidth
                val placeable = measurable.measure(
                    constraints.copy(minWidth = (constraints.minWidth + edge * 2).coerceAtMost(maxWidth), maxWidth = maxWidth),
                )
                layout((placeable.width - edge * 2).coerceAtLeast(0), placeable.height) { placeable.place(-edge, 0) }
            }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val f = (fade.toPx() / size.width).coerceIn(0f, 0.5f)
                drawRect(
                    Brush.horizontalGradient(0f to Color.Transparent, f to Color.Black, 1 - f to Color.Black, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn,
                )
            }
            .basicMarquee(
                iterations = Int.MAX_VALUE,
                animationMode = MarqueeAnimationMode.Immediately,
                initialDelayMillis = 1500,
                repeatDelayMillis = 2500,
                spacing = MarqueeSpacing.fractionOfContainer(1f / 4f),
                velocity = 36.dp,
            )
            .padding(horizontal = fade),
        style = style,
        maxLines = 1,
    )
}
