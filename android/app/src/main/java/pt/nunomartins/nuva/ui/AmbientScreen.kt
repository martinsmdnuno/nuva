package pt.nunomartins.nuva.ui

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.R
import pt.nunomartins.nuva.audio.Audio
import pt.nunomartins.nuva.audio.SpectrumShared
import pt.nunomartins.nuva.player.PlayerState
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** What the ambient screen shows; ← → cycle through them. The Mac app's `AmbientFace`. */
enum class AmbientFace(val label: Int) {
    Display(R.string.face_display), Clock(R.string.face_clock), Spectrum(R.string.face_spectrum),
    Meters(R.string.face_meters), Needles(R.string.face_needles), Valves(R.string.face_valves);

    fun moved(step: Int) = entries[(ordinal + step + entries.size) % entries.size]
}

/**
 * Ambient mode's options and timing, as on the Mac: the face, OLED protection (on by default: a slow
 * wander, dimmer static parts, a blinking colon, a new face every 20 minutes, rest after an hour
 * untouched) and dimming.
 */
object AmbientState {
    private var prefs: android.content.SharedPreferences? = null
    var face by mutableStateOf(AmbientFace.Display)
        private set
    var protectsOLED by mutableStateOf(true)
        private set
    var dims by mutableStateOf(false)
        private set
    /** Faces chosen with ← →, to show the face's name for a moment. */
    var changesByHand by mutableStateOf(0)
        private set
    var lastInteraction = System.currentTimeMillis()
        private set
    private var faceShownAt = System.currentTimeMillis()

    const val REST_AFTER = 3_600_000L
    const val CHANGE_FACE_AFTER = 1_200_000L

    fun init(context: Context) {
        if (prefs != null) return
        val p = context.getSharedPreferences("ambient", Context.MODE_PRIVATE)
        prefs = p
        face = AmbientFace.entries.firstOrNull { it.name == p.getString("face", null) } ?: AmbientFace.Display
        protectsOLED = p.getBoolean("oled", true)
        dims = p.getBoolean("dims", false)
    }

    fun choose(face: AmbientFace) {
        this.face = face
        faceShownAt = System.currentTimeMillis()
        prefs?.edit()?.putString("face", face.name)?.apply()
    }

    fun changeFace(step: Int) {
        choose(face.moved(step))
        changesByHand++
    }

    fun toggleOLED() {
        val on = !protectsOLED
        protectsOLED = on
        prefs?.edit()?.putBoolean("oled", on)?.apply()
    }

    fun toggleDims() {
        val on = !dims
        dims = on
        prefs?.edit()?.putBoolean("dims", on)?.apply()
    }

    fun noteInteraction() {
        lastInteraction = System.currentTimeMillis()
    }

    fun opened() {
        noteInteraction()
        faceShownAt = System.currentTimeMillis()
    }

    fun isResting(now: Long) = protectsOLED && now - lastInteraction > REST_AFTER

    /** With OLED protection, a new face every 20 minutes. */
    fun tick(now: Long) {
        if (protectsOLED && !isResting(now) && now - faceShownAt > CHANGE_FACE_AFTER) choose(face.moved(1))
    }
}

/** The ambient screen: one face at a time on the display colour, sized from the screen's width (`u` = 1% of it). */
@Composable
fun AmbientScreen(model: AppModel) {
    val state by model.player.state.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var pausedSince by remember { mutableStateOf<Long?>(null) }
    var showName by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        AmbientState.opened()
        while (true) {
            now = System.currentTimeMillis()
            AmbientState.tick(now)
            delay(1000)
        }
    }
    LaunchedEffect(state.isPlaying) { pausedSince = if (state.isPlaying) null else System.currentTimeMillis() }
    LaunchedEffect(AmbientState.changesByHand) {
        if (AmbientState.changesByHand == 0) return@LaunchedEffect
        showName = true
        delay(3000)
        showName = false
    }

    val protects = AmbientState.protectsOLED
    val idle = pausedSince?.let { now - it > 600_000 } ?: false
    val opacity = if (idle) 0.3f else if (AmbientState.dims) 0.4f else 1f

    BoxWithConstraints(Modifier.fillMaxSize().background(Tokens.display)) {
        val area = if (protects) 0.84f else 1f
        val u = maxWidth * area / 100
        if (AmbientState.isResting(now)) {
            val t = now / 1000.0
            Box(
                Modifier.align(Alignment.Center)
                    .offset(maxWidth * 0.4f * sin(t / 571).toFloat(), maxHeight * 0.4f * sin(t / 787 + 1).toFloat())
                    .alpha(0.6f),
            ) { Led(state.isPlaying, size = u) }
            return@BoxWithConstraints
        }
        val glow = model.glow
        Crossfade(glow, animationSpec = tween(1500), label = "glow") { field ->
            if (field != null) Glow(field, pulses = AmbientState.face == AmbientFace.Display, playing = state.isPlaying, opacity)
        }
        val (dx, dy) = drift(now, protects)
        // While scrubbing, every face shows where the track will go on from.
        val shown = state.scrub?.let { state.copy(position = it.target) } ?: state
        Box(
            Modifier
                .align(Alignment.Center)
                .fillMaxWidth(area)
                .fillMaxHeight(area)
                .offset(maxWidth * dx, maxHeight * dy)
                .padding(horizontal = u * 7, vertical = u * 6)
                .alpha(opacity),
        ) {
            val static = if (protects) 0.55f else 1f
            when (AmbientState.face) {
                AmbientFace.Display -> DisplayFace(model, shown, u, static)
                AmbientFace.Clock -> ClockFace(shown, u, now, protects, static)
                AmbientFace.Spectrum -> SpectrumFace(shown, u, static)
                AmbientFace.Meters -> MetersFace(shown, u, static)
                AmbientFace.Needles -> NeedlesFace(shown, u, static)
                AmbientFace.Valves -> ValvesFace(shown, u, static)
            }
        }
        val scrubbing = state.scrub != null
        AnimatedVisibility(showName || scrubbing, Modifier.align(Alignment.BottomCenter).padding(bottom = u * 2), enter = fadeIn(), exit = fadeOut()) {
            Text(
                if (scrubbing) stringResource(R.string.scrub_hint) else "←  ${stringResource(AmbientState.face.label).lowercase()}  →",
                Type.hint.copy(color = Tokens.inkMuted, fontSize = sp(u * 1.6f)),
                Modifier.clip(RoundedCornerShape(6.dp)).background(Tokens.surface0).padding(horizontal = 20.dp, vertical = 10.dp),
            )
        }
    }
}

/** Where the content sits: with OLED protection a slow wander over 8% of the screen each way, from two waves per axis. */
private fun drift(now: Long, protects: Boolean): Pair<Float, Float> {
    val t = now / 1000.0
    if (!protects) {
        val angle = (now / 60_000 % 24) / 24.0 * 2 * PI
        return (cos(angle) * 0.012).toFloat() to (sin(angle) * 0.008).toFloat()
    }
    fun wave(slow: Double, fast: Double, phase: Double) = 0.65 * sin(2 * PI * t / slow + phase) + 0.35 * sin(2 * PI * t / fast + phase * 2.3)
    return (wave(3187.0, 1279.0, 0.0) * 0.08).toFloat() to (wave(4253.0, 1531.0, 1.7) * 0.08).toFloat()
}

/** The cover's field behind the faces; on the Display face it breathes with the bass, between 70% and full. */
@Composable
private fun Glow(field: android.graphics.Bitmap, pulses: Boolean, playing: Boolean, opacity: Float) {
    val image = remember(field) { field.asImageBitmap() }
    var level = 1f
    if (pulses) {
        val pulse = remember { pt.nunomartins.nuva.ui.GlowPulse() }
        val time = meterFrames(playing)
        level = 0.7f + 0.3f * pulse.update(time, if (playing) Audio.spectrum.levels(Audio.clock.now()) else null).toFloat()
    }
    Image(image, null, Modifier.fillMaxSize().alpha(level * opacity), contentScale = ContentScale.FillBounds, filterQuality = FilterQuality.High)
}

@Composable
private fun sp(dp: Dp): TextUnit = with(LocalDensity.current) { dp.toSp() }

/** LED, format and the source: the line at the top of every face. */
@Composable
private fun MetaLine(state: PlayerState, u: Dp, right: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(u * 1.4f)) {
        Led(state.isPlaying, size = u)
        Box(Modifier.weight(1f)) {
            QualityBadge(state, Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.5f)), u * 1.2f, u * 0.45f)
        }
        Text(right, Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.7f)))
    }
}

@Composable
private fun Position(state: PlayerState, u: Dp, static: Float, modifier: Modifier = Modifier) {
    // Scrubbing, the bar is what is being moved: full brightness and a little thicker.
    val scrubbing = state.scrub != null
    PositionBar(
        if (state.duration > 0) (state.position / state.duration).toFloat() else 0f,
        modifier.alpha(if (scrubbing) 1f else static),
        height = maxOf(2.dp, u * if (scrubbing) 0.6f else 0.35f),
    )
}

/** The track at the foot of the animated faces: title and folders on the left, elapsed time on the right. */
@Composable
private fun TrackFoot(state: PlayerState, u: Dp) {
    val entry = state.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(u * 2)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(u * 0.6f)) {
            ScrollingText(entry?.title ?: stringResource(R.string.no_track), Type.title.copy(color = if (entry == null) Tokens.displayMuted else Tokens.displayInk, fontSize = sp(u * 2.8f)))
            ScrollingText(entry?.folderLine.orEmpty(), Type.body.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.9f)))
        }
        Text(clock(state.position), Type.displayTime.copy(color = Tokens.displayInk, fontSize = sp(u * 4.4f), lineHeight = sp(u * 5f)))
    }
}

/** The window's display at the scale of the room. */
@Composable
private fun DisplayFace(model: AppModel, state: PlayerState, u: Dp, static: Float) {
    val entry = state.current
    Column(Modifier.fillMaxSize()) {
        MetaLine(state, u, stringResource(R.string.source_server))
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(u * 2.4f)) {
            val cover = model.cover
            if (model.showArtwork && cover != null) {
                Image(remember(cover) { cover.asImageBitmap() }, null, Modifier.size(u * 10).clip(RoundedCornerShape(3.dp)), contentScale = ContentScale.Crop)
            }
            Column(verticalArrangement = Arrangement.spacedBy(u * 1.2f)) {
                ScrollingText(entry?.title ?: stringResource(R.string.no_track), Type.title.copy(color = if (entry == null) Tokens.displayMuted else Tokens.displayInk, fontSize = sp(u * 5.6f), lineHeight = sp(u * 6.6f)))
                ScrollingText(entry?.folderLine ?: stringResource(R.string.choose_folder), Type.body.copy(color = Tokens.displayMuted, fontSize = sp(u * 2.3f), lineHeight = sp(u * 3f)))
            }
        }
        Spacer(Modifier.weight(1f))
        Row(Modifier.fillMaxWidth().padding(bottom = u * 2), verticalAlignment = Alignment.Bottom) {
            Text(clock(state.position), Type.displayTime.copy(color = Tokens.displayInk, fontSize = sp(u * 13f), lineHeight = sp(u * 14f)), Modifier.weight(1f))
            Text(clock(state.duration), Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 2.2f)))
        }
        Position(state, u, static)
    }
}

/** The time of day as the subject, the playing track on one line below; the colon blinks with OLED protection. */
@Composable
private fun ClockFace(state: PlayerState, u: Dp, now: Long, blinks: Boolean, static: Float) {
    val date = Date(now)
    val colon = !blinks || (now / 1000) % 2 == 0L
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(u * 1.4f)) {
        Spacer(Modifier.weight(1f))
        val style = Type.displayTime.copy(color = Tokens.displayInk, fontSize = sp(u * 20f), lineHeight = sp(u * 22f))
        Row {
            Text(SimpleDateFormat("HH", Locale.getDefault()).format(date), style)
            Text(":", style, Modifier.alpha(if (colon) 1f else 0f))
            Text(SimpleDateFormat("mm", Locale.getDefault()).format(date), style)
        }
        Text(SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(date).lowercase(), Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.9f)))
        Spacer(Modifier.weight(1f))
        state.current?.let { entry ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(u * 1.4f)) {
                Led(state.isPlaying, size = u)
                ScrollingText("${entry.title}  ·  ${entry.folderLine}", Type.body.copy(color = Tokens.displayInk, fontSize = sp(u * 2.1f)), Modifier.width(u * 60))
            }
            Position(state, u, static, Modifier.width(u * 30).padding(top = u * 1.4f))
        }
    }
}

/** 28 bands from 20 Hz to 20 kHz as solid bars in display-ink, each with its held peak as a thin cap in led. */
@Composable
private fun SpectrumFace(state: PlayerState, u: Dp, static: Float) {
    val meter = remember { SpectrumMeter(SpectrumShared.FINE_BANDS, floor = -62f, ceiling = -12f, fall = 0.9f, attack = 0.025f, gravity = 2.4f) }
    Column(Modifier.fillMaxSize()) {
        MetaLine(state, u, "20 Hz – 20 kHz")
        Spacer(Modifier.height(u * 3))
        val time = meterFrames(state.isPlaying)
        meter.update(time, if (state.isPlaying) Audio.spectrum.fineLevels(Audio.clock.now()) else null)
        val ink = Tokens.displayInk
        val led = Tokens.led
        Canvas(Modifier.fillMaxWidth().weight(1f)) {
            if (time < 0) return@Canvas
            val columns = meter.levels.size
            val gap = u.toPx() * 0.75f
            val width = (size.width - gap * (columns - 1)) / columns
            val cap = maxOf(2f, u.toPx() * 0.35f)
            for (c in 0 until columns) {
                val x = c * (width + gap)
                val bar = meter.levels[c] * (size.height - cap * 2)
                if (bar > 0) drawRect(ink, Offset(x, size.height - bar), Size(width, bar))
                val peak = meter.peaks[c] * (size.height - cap * 2)
                if (meter.peaks[c] > 0) drawRect(led, Offset(x, size.height - peak - cap * 1.6f), Size(width, cap))
            }
        }
        Position(state, u, static, Modifier.padding(top = u * 1.6f, bottom = u * 3))
        TrackFoot(state, u)
    }
}

/** Left and right as two ladders of segments: RMS lit in led, the held peak in display-ink, a dBFS scale below. */
@Composable
private fun MetersFace(state: PlayerState, u: Dp, static: Float) {
    val meter = remember { SpectrumMeter(2, floor = -48f, ceiling = 0f, fall = 1.3f, attack = 0.02f, gravity = 1.8f) }
    val segments = 40
    val marks = listOf(-48, -36, -24, -18, -12, -6, -3, 0)
    val measurer = rememberTextMeasurer()
    Column(Modifier.fillMaxSize()) {
        MetaLine(state, u, stringResource(R.string.source_server))
        Spacer(Modifier.weight(1f))
        val time = meterFrames(state.isPlaying)
        meter.update(time, if (state.isPlaying) Audio.spectrum.stereo(Audio.clock.now())?.let { floatArrayOf(it[0], it[1]) } else null)
        val led = Tokens.led
        val ink = Tokens.displayInk
        val track = Tokens.displayTrack
        val muted = Tokens.displayMuted
        val metaStyle = Type.displayMeta.copy(color = muted, fontSize = sp(u * 1.5f))
        val channelStyle = Type.displayMeta.copy(color = muted, fontSize = sp(u * 2f))
        Canvas(Modifier.fillMaxWidth().height(u * 15.5f)) {
            if (time < 0) return@Canvas
            val labelWidth = u.toPx() * 4.5f
            val ladder = size.width - labelWidth
            val gap = u.toPx() * 0.45f
            val width = (ladder - gap * (segments - 1)) / segments
            val rowHeight = u.toPx() * 4.2f
            for (channel in 0..1) {
                val y = channel * (rowHeight + u.toPx() * 2.6f)
                drawLabel(measurer, if (channel == 0) "L" else "R", channelStyle, Offset(0f, y + rowHeight / 2), centred = false)
                val exact = meter.levels[channel] * segments
                val lit = exact.toInt()
                val held = (meter.peaks[channel] * segments).let { kotlin.math.round(it).toInt() } - 1
                for (s in 0 until segments) {
                    val x = labelWidth + s * (width + gap)
                    val color = if (s < lit) led else if (s == held && held >= lit) ink else track
                    drawRoundRect(color, Offset(x, y), Size(width, rowHeight), CornerRadius(u.toPx() * 0.15f))
                    // The segment at the level's edge lights in part, so the bar glides instead of stepping.
                    if (s == lit && s != held && exact > lit) drawRoundRect(led.copy(alpha = exact - lit), Offset(x, y), Size(width, rowHeight), CornerRadius(u.toPx() * 0.15f))
                }
            }
            val scaleY = 2 * rowHeight + u.toPx() * 2.6f + u.toPx() * 2.4f
            for (mark in marks) {
                val x = labelWidth + (mark + 48) / 48f * ladder
                drawLabel(measurer, mark.toString(), metaStyle, Offset(x.coerceIn(labelWidth + u.toPx(), size.width - u.toPx()), scaleY))
            }
        }
        Spacer(Modifier.weight(1f))
        Position(state, u, static, Modifier.padding(bottom = u * 3))
        TrackFoot(state, u)
    }
}

private fun DrawScope.drawLabel(measurer: TextMeasurer, text: String, style: TextStyle, at: Offset, centred: Boolean = true) {
    val layout = measurer.measure(text, style)
    val x = if (centred) at.x - layout.size.width / 2 else at.x
    drawText(layout, topLeft = Offset(x, at.y - layout.size.height / 2))
}

/** VU deflection of a level: proportional to voltage, so -20 sits just right of the pin and 0 VU at about 70%. */
private fun position(vu: Float) = VUNeedle.deflection(vu.toDouble()).toFloat()

/**
 * Two backlit VU meters under glass: a printed arc from -20 to +3 VU with the 0 to +3 zone heavier, a
 * tapered needle with its shadow, and a peak light within 1 dB of full scale. 0 VU is -14 dBFS RMS.
 */
@Composable
private fun NeedlesFace(state: PlayerState, u: Dp, static: Float) {
    val meter = remember { NeedleMeter() }
    val measurer = rememberTextMeasurer()
    Column(Modifier.fillMaxSize()) {
        MetaLine(state, u, stringResource(R.string.source_server))
        Spacer(Modifier.weight(1f))
        val time = meterFrames(state.isPlaying)
        meter.update(time, if (state.isPlaying) Audio.spectrum.stereo(Audio.clock.now()) else null)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(u * 4)) {
            for (channel in 0..1) {
                VuPanel(meter.levels[channel], meter.peaks[channel] > -1f, channel, u, static, measurer, Modifier.weight(1f).aspectRatio(1.9f))
            }
        }
        Spacer(Modifier.weight(1f))
        Position(state, u, static, Modifier.padding(bottom = u * 3))
        TrackFoot(state, u)
    }
}

@Composable
private fun VuPanel(deflection: Float, clipping: Boolean, channel: Int, u: Dp, static: Float, measurer: TextMeasurer, modifier: Modifier) {
    val ink = Tokens.ink
    val led = Tokens.led
    val display = Tokens.display
    val sheen = Tokens.displayInk
    val markStyle = Type.displayMeta.copy(color = display.copy(alpha = 0.85f), fontSize = sp(u * 1.25f))
    val vuStyle = Type.displayMeta.copy(color = display.copy(alpha = 0.85f), fontSize = sp(u * 1.6f))
    val channelStyle = Type.displayMeta.copy(color = display.copy(alpha = 0.6f), fontSize = sp(u * 1.3f))
    Canvas(modifier) {
        val unit = u.toPx()
        val w = size.width
        val h = size.height
        val corner = CornerRadius(unit * 0.4f)
        val panel = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(Rect(Offset.Zero, size), corner)) }
        // The lamp: the skin's ink warmed by its accent, lit from behind by one bulb.
        drawRoundRect(ink, cornerRadius = corner)
        drawRoundRect(led.copy(alpha = 0.5f), cornerRadius = corner)
        drawRoundRect(Brush.radialGradient(listOf(display.copy(alpha = 0f), display.copy(alpha = 0.4f)), Offset(w / 2, h * 0.6f), w * 0.62f), cornerRadius = corner)
        drawRoundRect(display.copy(alpha = (1 - static) * 0.55f), cornerRadius = corner)

        val printed = display.copy(alpha = 0.85f)
        val pivot = Offset(w / 2, h * 1.18f)
        val radius = h * 0.95f
        val sweep = 0.78
        fun angle(p: Float) = -PI / 2 - sweep + 2 * sweep * p
        fun point(p: Float, r: Float) = Offset(pivot.x + cos(angle(p)).toFloat() * r, pivot.y + sin(angle(p)).toFloat() * r)
        fun arc(from: Float, to: Float, r: Float, width: Float) {
            val start = Math.toDegrees(angle(from)).toFloat()
            val end = Math.toDegrees(angle(to)).toFloat()
            drawArc(printed, start, end - start, false, Offset(pivot.x - r, pivot.y - r), Size(r * 2, r * 2), style = Stroke(width))
        }
        arc(position(-20f), 1f, radius, maxOf(1f, unit * 0.12f))
        arc(position(0f), 1f, radius + unit * 0.35f, unit * 0.6f)
        val labelled = setOf(-20, -10, -7, -5, -3, 0, 3)
        for (mark in listOf(-20, -10, -7, -5, -3, -1, 0, 1, 2, 3)) {
            val p = position(mark.toFloat())
            drawLine(printed, point(p, radius), point(p, radius + unit * if (mark in labelled) 1.1f else 0.7f), maxOf(1f, unit * 0.14f))
            if (mark in labelled) drawLabel(measurer, if (mark > 0) "+$mark" else "$mark", markStyle, point(p, radius + unit * 2.2f))
        }
        drawLabel(measurer, "VU", vuStyle, Offset(w / 2, h * 0.62f))
        drawLabel(measurer, if (channel == 0) "L" else "R", channelStyle, Offset(unit * 1.6f, h - unit * 1.4f))

        // The needle, tapered from its hidden pivot to a fine tip past the arc, with its shadow on the dial.
        val a = angle(deflection)
        val along = Offset(cos(a).toFloat(), sin(a).toFloat())
        val across = Offset(-sin(a).toFloat(), cos(a).toFloat())
        fun needle(shift: Offset): Path {
            val wide = maxOf(1.2f, unit * 0.13f)
            val fine = maxOf(0.6f, unit * 0.045f)
            val base = radius * 0.19f
            val tip = radius + unit * 1.2f
            fun at(r: Float, side: Float) = pivot + along * r + across * side + shift
            return Path().apply {
                moveTo(at(base, -wide).x, at(base, -wide).y)
                lineTo(at(tip, -fine).x, at(tip, -fine).y)
                lineTo(at(tip, fine).x, at(tip, fine).y)
                lineTo(at(base, wide).x, at(base, wide).y)
                close()
            }
        }
        clipPath(panel) {
            drawPath(needle(Offset(unit * 0.22f, unit * 0.4f)), display.copy(alpha = 0.22f))
            drawPath(needle(Offset.Zero), display)
            // Under glass: a faint sheen across the top and a shadow inside the opening.
            drawRect(Brush.linearGradient(listOf(sheen.copy(alpha = 0.07f), sheen.copy(alpha = 0f)), Offset(w * 0.3f, 0f), Offset(w * 0.45f, h * 0.5f)))
            drawRoundRect(display.copy(alpha = 0.35f), cornerRadius = corner, style = Stroke(unit * 1.2f))
        }
        // Peak light, top right, with its glow on the panel.
        val light = Offset(w - unit * 1.55f, unit * 1.45f)
        if (clipping) drawCircle(Brush.radialGradient(listOf(led.copy(alpha = 0.8f), led.copy(alpha = 0f)), light, unit * 1.2f), unit * 1.2f, light)
        drawCircle(if (clipping) led else display.copy(alpha = 0.35f), unit * 0.45f, light)
    }
}

/** Two valves in their cage, the filaments glowing with each channel (in led), warm while paused. */
@Composable
private fun ValvesFace(state: PlayerState, u: Dp, static: Float) {
    val meter = remember { SlowMeter(floor = -40f, ceiling = -8f, rise = 4f, fall = 1.5f) }
    val measurer = rememberTextMeasurer()
    Column(Modifier.fillMaxSize()) {
        MetaLine(state, u, stringResource(R.string.source_server))
        Spacer(Modifier.weight(1f))
        val time = meterFrames(state.isPlaying)
        meter.update(time, if (state.isPlaying) Audio.spectrum.stereo(Audio.clock.now()) else null)
        Row(Modifier.fillMaxWidth().weight(4f), horizontalArrangement = Arrangement.spacedBy(u * 10, Alignment.CenterHorizontally)) {
            for (channel in 0..1) Valve(meter.levels[channel], state.current != null, channel, u, measurer, Modifier.fillMaxHeight().aspectRatio(0.62f))
        }
        Spacer(Modifier.weight(1f))
        Position(state, u, static, Modifier.padding(bottom = u * 3))
        TrackFoot(state, u)
    }
}

@Composable
private fun Valve(glow: Float, heated: Boolean, channel: Int, u: Dp, measurer: TextMeasurer, modifier: Modifier) {
    val led = Tokens.led
    val metal = Tokens.displayTrack
    val glass = Tokens.displayMuted.copy(alpha = 0.8f)
    val hot = Tokens.displayInk
    val labelStyle = Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.5f))
    Canvas(modifier) {
        val unit = u.toPx()
        val w = size.width
        val h = size.height
        val line = maxOf(1f, unit * 0.14f)
        val level = if (heated) 0.2f + 0.8f * glow else 0f
        val left = w * 0.24f; val right = w * 0.76f; val top = h * 0.16f; val shoulder = h * 0.3f; val bottom = h * 0.86f
        val envelope = Path().apply {
            moveTo(left, bottom); lineTo(left, shoulder)
            quadraticTo(w / 2, top - h * 0.1f, right, shoulder)
            lineTo(right, bottom)
        }
        val centre = Offset(w / 2, h * 0.57f)
        if (level > 0) {
            drawRect(Brush.radialGradient(listOf(led.copy(alpha = 0.35f * level), led.copy(alpha = 0f)), centre, w * (0.35f + 0.25f * level)))
            val inside = Path().apply { addPath(envelope); close() }
            clipPath(inside) {
                drawRect(Brush.radialGradient(listOf(led.copy(alpha = level), led.copy(alpha = 0.3f * level)), centre, h * (0.18f + 0.35f * level)))
            }
        }
        drawPath(envelope, glass, style = Stroke(line))
        drawOval(metal, Offset(w * 0.38f, h * 0.2f), Size(w * 0.24f, h * 0.07f))
        drawRoundRect(metal, Offset(w * 0.36f, h * 0.42f), Size(w * 0.28f, h * 0.3f), CornerRadius(unit * 0.3f), style = Stroke(w * 0.035f))
        val filamentTop = Offset(w / 2, h * 0.44f)
        val filamentBottom = Offset(w / 2, h * 0.7f)
        drawLine(if (level > 0) led.copy(alpha = 0.5f + 0.5f * level) else metal, filamentTop, filamentBottom, line * 1.4f, StrokeCap.Round)
        if (level > 0.4f) drawLine(hot.copy(alpha = ((level - 0.4f) * 1.4f).coerceAtMost(1f)), filamentTop, filamentBottom, line * 0.6f, StrokeCap.Round)
        drawRoundRect(metal, Offset(w * 0.2f, bottom), Size(w * 0.6f, h * 0.08f), CornerRadius(unit * 0.2f))
        for (x in listOf(w * 0.13f, w * 0.87f)) drawRoundRect(metal, Offset(x - w * 0.025f, h * 0.08f), Size(w * 0.05f, h * 0.8f), CornerRadius(unit * 0.3f))
        for (y in listOf(h * 0.09f, h * 0.36f, h * 0.66f)) drawRoundRect(metal, Offset(w * 0.08f, y), Size(w * 0.84f, h * 0.028f), CornerRadius(unit * 0.3f))
        drawLabel(measurer, if (channel == 0) "L" else "R", labelStyle, Offset(w / 2, h * 0.98f))
    }
}
