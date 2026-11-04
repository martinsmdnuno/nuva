package pt.nunomartins.nuva.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.composed
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

val KeyShape = RoundedCornerShape(6.dp)

/** The three key tones, as on a Braun calculator; read from the current skin. */
enum class Tone {
    Play, Transport, Mode;

    val face: Color get() = when (this) { Play -> Tokens.keyPlay; Transport -> Tokens.keyFace; Mode -> Tokens.keyMode }
    /** The face while the key is held down: 85% of it. */
    val pressed: Color get() = when (this) { Play -> Tokens.keyPlayPressed; Transport -> Tokens.keyFacePressed; Mode -> Tokens.keyModePressed }
    val ink: Color get() = when (this) { Play, Transport -> Tokens.keyInk; Mode -> Tokens.keyModeInk }
}

/**
 * A flat key, as on a Braun calculator: no outline, the face is the edge. Pressed, it darkens
 * and goes down a point; with focus it gets the 2-point focus ring. `led`: null for keys without state.
 */
@Composable
fun Key(
    tone: Tone,
    width: Dp,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    text: String? = null,
    led: Boolean? = null,
    description: String? = null,
    height: Dp? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val pressed by interaction.collectIsPressedAsState()
    val face by animateColorAsState(if (pressed) tone.pressed else tone.face, tween(60), label = "face")
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        if (led != null) {
            Led(led)
            Spacer(Modifier.height(5.dp))
        }
        Box(
            Modifier
                .offset(y = if (pressed) 2.dp else 0.dp)
                .border(2.dp, if (focused) Tokens.focus else Color.Transparent, RoundedCornerShape(8.dp))
                .padding(3.dp)
                .clip(KeyShape)
                .background(face)
                .clickable(interactionSource = interaction, indication = null, onClick = onClick)
                .height(height ?: if (text != null) 56.dp else 64.dp)
                .then(if (width > 0.dp) Modifier.width(width) else Modifier.fillMaxWidth()),
            contentAlignment = Alignment.Center,
        ) {
            if (icon != null) {
                Image(icon, description, Modifier.size(30.dp), colorFilter = ColorFilter.tint(tone.ink))
            } else if (text != null) {
                BasicText(text, Modifier.padding(horizontal = 20.dp), style = Type.label.copy(color = tone.ink), maxLines = 1)
            }
        }
    }
}

/** A key group's name, printed on the chassis in lowercase, under the keys. */
@Composable
fun Legend(text: String, modifier: Modifier = Modifier) {
    BasicText(text.lowercase(), modifier, style = Type.legend)
}

/** State LED: amber on, grey off. Lights in 80 ms and fades in 350 ms, like a filament. */
@Composable
fun Led(on: Boolean, size: Dp = 8.dp) {
    val color by animateColorAsState(if (on) Tokens.led else Tokens.ledOff, tween(if (on) 80 else 350), label = "led")
    Box(Modifier.size(size).clip(CircleShape).background(color))
}

/** The position bar inside the display: a 4-point line, the played part in display-ink. */
@Composable
fun PositionBar(fraction: Float, modifier: Modifier = Modifier, height: Dp = 4.dp) {
    Box(modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(2.dp)).background(Tokens.displayTrack)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(height).background(Tokens.displayInk))
    }
}

/** A list row (folder or track). Focus shows as surface-2, the playing track in signal with its LED. */
@Composable
fun ListRow(
    name: String,
    detail: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isFolder: Boolean = false,
    playing: Boolean = false,
    onLongClick: (() -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val background by animateColorAsState(if (focused) Tokens.surface2 else Color.Transparent, tween(120), label = "row")
    Row(
        modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(background)
            .remoteClick(interaction, onClick, onLongClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.width(24.dp), contentAlignment = Alignment.Center) {
            when {
                isFolder -> Image(Icons.folder, null, Modifier.size(22.dp), colorFilter = ColorFilter.tint(Tokens.inkMuted))
                playing -> Led(true)
            }
        }
        // Long names slide while the row has the focus, so they can be read whole.
        ScrollingText(name, Type.body.copy(color = if (playing) Tokens.signal else Tokens.ink), Modifier.weight(1f), moving = focused)
        if (detail != null) Text(detail, (if (isFolder) Type.body.copy(fontSize = Type.legend.fontSize) else Type.duration).copy(color = Tokens.inkMuted))
    }
}

/** One line of text that ends with an ellipsis, never in the middle. */
@Composable
fun Text(text: String, style: TextStyle, modifier: Modifier = Modifier, maxLines: Int = 1) {
    BasicText(text, modifier, style = style, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

/** 83 → "01:23"; an hour or more → "1:02:03". */
fun clock(seconds: Double): String {
    val s = seconds.toLong().coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%02d:%02d".format(s / 60, s % 60)
}

/** Durations in lists: "4:17". */
fun minutes(seconds: Double): String {
    val s = seconds.toLong()
    return "%d:%02d".format(s / 60, s % 60)
}

/**
 * OK on the remote: a press is a click, holding it is a long click (the TV's "more" gesture, like
 * the Mac's ⌘Enter and context menus). Focusable for the D-pad.
 */
fun Modifier.remoteClick(interaction: MutableInteractionSource, onClick: () -> Unit, onLongClick: (() -> Unit)?): Modifier = composed {
    var held by remember { mutableStateOf(false) }
    this
        .onPreviewKeyEvent { event ->
            val ok = event.key == Key.DirectionCenter || event.key == Key.Enter || event.key == Key.NumPadEnter
            if (!ok) return@onPreviewKeyEvent false
            when (event.type) {
                KeyEventType.KeyDown -> {
                    if (event.nativeKeyEvent.repeatCount == 1 && onLongClick != null) {
                        held = true
                        onLongClick()
                    }
                    true
                }
                KeyEventType.KeyUp -> {
                    if (!held) onClick()
                    held = false
                    true
                }
                else -> false
            }
        }
        .focusable(interactionSource = interaction)
}
