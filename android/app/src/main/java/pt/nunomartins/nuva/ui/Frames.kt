package pt.nunomartins.nuva.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.MarqueeAnimationMode
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

/** Text that slides when it doesn't fit, so long names can be read whole: always, or only with focus. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ScrollingText(text: String, style: TextStyle, modifier: Modifier = Modifier, moving: Boolean = true) {
    BasicText(
        text,
        modifier.basicMarquee(
            iterations = if (moving) Int.MAX_VALUE else 0,
            animationMode = MarqueeAnimationMode.Immediately,
            initialDelayMillis = 1500,
            repeatDelayMillis = 2500,
            velocity = androidx.compose.ui.unit.Dp(40f),
        ),
        style = style,
        maxLines = 1,
    )
}
