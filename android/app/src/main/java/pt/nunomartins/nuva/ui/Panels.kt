package pt.nunomartins.nuva.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Canvas
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.Overlay
import pt.nunomartins.nuva.R
import pt.nunomartins.nuva.artwork.ArtworkOrigin
import pt.nunomartins.nuva.audio.Audio
import pt.nunomartins.nuva.audio.Equalizer

/** What sits over the player, with its own focus; Back closes it. */
@Composable
fun Overlays(model: AppModel, onLeave: () -> Unit) {
    when (val overlay = model.overlay) {
        null -> Unit
        Overlay.Equalizer -> EqualizerPanel(model)
        Overlay.Settings -> SettingsPanel(model)
        Overlay.Terms -> TermsPanel(model)
        Overlay.ConfirmExit -> ConfirmExit(model, onLeave)
        is Overlay.QueueActions -> QueueActions(model, overlay.index)
    }
}

/** A panel on surface-1, over the chassis darkened behind it (by the display's own dark). */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
private fun Panel(width: Dp, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Tokens.display.copy(alpha = 0.55f)), contentAlignment = Alignment.Center) {
        // The remote's focus stays inside the panel until it closes.
        Column(
            Modifier.width(width).clip(RoundedCornerShape(10.dp)).background(Tokens.surface1)
                .focusProperties { exit = { FocusRequester.Cancel } }.focusGroup()
                .padding(horizontal = 32.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            content = content,
        )
    }
}

@Composable
private fun PanelTitle(text: String) = Text(text, Type.title.copy(color = Tokens.ink))

/** A focusable option row: label on the left, value or LED on the right. */
@Composable
private fun OptionRow(label: String, value: String? = null, led: Boolean? = null, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Row(
        modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(6.dp)).background(rowBackground(focused))
            .remoteClick(interaction, onClick, null).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, Type.body.copy(color = Tokens.ink), Modifier.weight(1f))
        if (value != null) Text(value, Type.body.copy(color = Tokens.inkMuted))
        if (led != null) Led(led)
    }
}

/**
 * The on/off key with its LED, the presets, then the 10 faders, as on the Mac. Moving and adjusting
 * are apart: the arrows move the focus between the key, the presets and the bands; OK on a band
 * takes hold of it (its LED lights) and then ↑ ↓ move it half a decibel at a time; OK or Back lets
 * go. Same bands and presets as the Mac.
 */
@Composable
private fun EqualizerPanel(model: AppModel) {
    val eq = Audio.equalizer
    val presets = remember { FocusRequester() }
    Panel(820.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            PanelTitle(stringResource(R.string.equalizer))
            Spacer(Modifier.weight(1f))
            Key(Tone.Mode, 160.dp, { eq.toggle() }, text = stringResource(if (eq.enabled) R.string.on else R.string.off), led = eq.enabled)
        }
        // The presets in two rows of four; the active one lit by its LED.
        for ((r, row) in Equalizer.presets.chunked(4).withIndex()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for ((i, preset) in row.withIndex()) {
                    val active = eq.enabled && eq.preset == preset.key
                    val modifier = Modifier.weight(1f).then(if (r == 0 && i == 0) Modifier.focusRequester(presets) else Modifier)
                    Key(Tone.Mode, 0.dp, { eq.apply(preset) }, text = presetName(preset.key), led = active, modifier = modifier, height = 44.dp)
                }
            }
        }
        Row(Modifier.fillMaxWidth().height(210.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            for (band in 0 until 10) {
                Fader(band, eq.gains[band], eq.enabled) { eq.nudge(band, it) }
            }
        }
        Legend(stringResource(R.string.eq_hint))
    }
    LaunchedEffect(Unit) { runCatching { presets.requestFocus() } }
}

@Composable
private fun Fader(band: Int, gain: Float, enabled: Boolean, nudge: (Int) -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    // Held: ↑ ↓ adjust the band. Not held: they move the focus like everywhere else.
    var held by remember { mutableStateOf(false) }
    // The key that let go was pressed while held: its release is ours too, not the panel's.
    var swallow by remember { mutableStateOf<Key?>(null) }
    LaunchedEffect(focused) { if (!focused) held = false }
    val fill = if (enabled) Tokens.fill else Tokens.track
    val track = Tokens.track
    Column(
        Modifier.width(64.dp).fillMaxHeight()
            .border(2.dp, if (focused) Tokens.focus else Color.Transparent, RoundedCornerShape(6.dp))
            .onPreviewKeyEvent { e ->
                val ok = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
                if (e.type == KeyEventType.KeyUp) {
                    if (swallow == e.key) { swallow = null; return@onPreviewKeyEvent true }
                    if (ok) { held = true; return@onPreviewKeyEvent true }
                    return@onPreviewKeyEvent false
                }
                if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when {
                    ok && held -> { held = false; swallow = e.key; true }
                    ok -> true
                    e.key == Key.Back && held -> { held = false; swallow = e.key; true }
                    held && e.key == Key.DirectionUp -> { nudge(1); true }
                    held && e.key == Key.DirectionDown -> { nudge(-1); true }
                    // Held, ← → stay on the band; OK or Back lets go first.
                    held && (e.key == Key.DirectionLeft || e.key == Key.DirectionRight) -> true
                    else -> false
                }
            }
            .focusable(interactionSource = interaction)
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Led(held, size = 6.dp)
        Text((if (gain > 0) "+" else "") + if (gain % 1f == 0f) gain.toInt().toString() else gain.toString(), Type.hint.copy(color = Tokens.ink))
        Canvas(Modifier.width(24.dp).weight(1f)) {
            val x = size.width / 2
            drawRect(track, Offset(x - 2.dp.toPx(), 0f), Size(4.dp.toPx(), size.height))
            drawRect(track, Offset(0f, size.height / 2 - 1), Size(size.width, 2f))
            val y = size.height * (1 - (gain - Equalizer.MIN) / (Equalizer.MAX - Equalizer.MIN))
            // The focus ring shows the focus; the accent stays on the LEDs.
            drawRect(fill, Offset(0f, y - 4.dp.toPx()), Size(size.width, 8.dp.toPx()))
        }
        Text(Equalizer.labels[band], Type.hint)
    }
}

/** The Mac's View menu and app menu, for the remote. */
@Composable
private fun SettingsPanel(model: AppModel) {
    val first = remember { FocusRequester() }
    val updates = model.updates
    Panel(720.dp) {
        PanelTitle(stringResource(R.string.settings_title))
        LazyColumn(Modifier.height(400.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            item { Legend(stringResource(R.string.section_look), Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp)) }
            item {
                OptionRow(stringResource(R.string.skin), Look.skin.label, modifier = Modifier.focusRequester(first)) {
                    Look.choose(Skin.entries[(Look.skin.ordinal + 1) % Skin.entries.size])
                }
            }
            item {
                OptionRow(stringResource(R.string.font), Look.fontChoice?.label ?: stringResource(R.string.font_follows, Look.skin.fontSet.label)) {
                    val sets = listOf<FontSet?>(null) + FontSet.entries
                    Look.choose(sets[(sets.indexOf(Look.fontChoice) + 1) % sets.size])
                }
            }
            item {
                // With artwork on, where the playing album's cover came from (or that none was found).
                val origin = when (model.artworkOrigin) {
                    ArtworkOrigin.Folder -> stringResource(R.string.artwork_folder)
                    ArtworkOrigin.Online -> stringResource(R.string.artwork_online)
                    ArtworkOrigin.None -> stringResource(R.string.artwork_none)
                    ArtworkOrigin.Offline -> stringResource(R.string.artwork_offline)
                    null -> null
                }
                OptionRow(stringResource(R.string.show_artwork), origin?.takeIf { model.showArtwork }, led = model.showArtwork) { model.toggleShowArtwork() }
            }
            item { OptionRow(stringResource(R.string.show_spectrum), led = model.showSpectrum) { model.toggleShowSpectrum() } }
            item { Legend(stringResource(R.string.section_ambient), Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp)) }
            item { OptionRow(stringResource(R.string.ambient_face), stringResource(AmbientState.face.label)) { AmbientState.choose(AmbientState.face.moved(1)) } }
            item { OptionRow(stringResource(R.string.oled), led = AmbientState.protectsOLED) { AmbientState.toggleOLED() } }
            item { OptionRow(stringResource(R.string.dim), led = AmbientState.dims) { AmbientState.toggleDims() } }
            item { OptionRow(stringResource(R.string.auto_ambient), led = model.autoAmbient) { model.toggleAutoAmbient() } }
            item { Legend("NuVa ${AppModel.VERSION}", Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp)) }
            item {
                val status = when {
                    updates.checking -> stringResource(R.string.checking)
                    updates.available != null -> stringResource(R.string.update_available, updates.available!!)
                    updates.upToDate == true -> stringResource(R.string.up_to_date)
                    updates.upToDate == false -> stringResource(R.string.update_failed)
                    else -> null
                }
                OptionRow(stringResource(R.string.check_updates), status, led = updates.available?.let { true }) { model.checkUpdates() }
            }
            item { OptionRow(stringResource(R.string.terms)) { model.overlay = Overlay.Terms } }
            item { OptionRow(stringResource(R.string.sign_out), model.savedUser) { model.signOut() } }
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

/** TERMS.md, bundled with the app as on the Mac, as plain text. */
@Composable
private fun TermsPanel(model: AppModel) {
    val context = LocalContext.current
    val paragraphs = remember { terms(context) }
    val first = remember { FocusRequester() }
    Panel(900.dp) {
        PanelTitle(stringResource(R.string.terms))
        LazyColumn(Modifier.height(400.dp)) {
            items(paragraphs.size) { i ->
                val (heading, text) = paragraphs[i]
                // Each paragraph takes the focus in turn, so ↓ scrolls the text.
                val interaction = remember { MutableInteractionSource() }
                val focused by interaction.collectIsFocusedAsState()
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(rowBackground(focused))
                        .then(if (i == 0) Modifier.focusRequester(first) else Modifier).focusable(interactionSource = interaction)
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    if (heading) Text(text, Type.label.copy(color = Tokens.ink), maxLines = 3)
                    else Text(text, Type.body.copy(color = Tokens.inkMuted, fontSize = Type.label.fontSize), maxLines = 20)
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}

/** TERMS.md as (is heading, text) paragraphs, in the system's language (its second half is Portuguese). */
private fun terms(context: Context): List<Pair<Boolean, String>> {
    val all = context.assets.open("TERMS.md").bufferedReader().use { it.readText() }
    val halves = all.split(Regex("""\n---\n"""))
    val portuguese = context.resources.configuration.locales[0].language == "pt"
    val text = if (portuguese && halves.size > 1) halves[1] else halves[0]
    return text.split(Regex("""\n\s*\n""")).map { it.trim() }.filter { it.isNotEmpty() }.map { block ->
        val clean = block.replace(Regex("""\[([^\]]+)]\([^)]+\)"""), "$1").replace("**", "").replace("*", "").replace(Regex("""^- """, RegexOption.MULTILINE), "· ")
        if (clean.startsWith("#")) true to clean.trimStart('#', ' ') else false to clean
    }
}

/** Back on the main screen: leave or stay. The music keeps playing either way, as when the Mac's window closes. */
@Composable
private fun ConfirmExit(model: AppModel, onLeave: () -> Unit) {
    val stay = remember { FocusRequester() }
    Panel(560.dp) {
        PanelTitle(stringResource(R.string.leave_title))
        Text(stringResource(R.string.leave_note), Type.body.copy(color = Tokens.inkMuted), maxLines = 3)
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Key(Tone.Mode, 160.dp, { model.overlay = null }, Modifier.focusRequester(stay), text = stringResource(R.string.stay))
            Key(Tone.Mode, 160.dp, onLeave, text = stringResource(R.string.leave))
        }
    }
    LaunchedEffect(Unit) { runCatching { stay.requestFocus() } }
}

/** Holding OK on a queue row: move it, remove it, or clear the queue (⌥⌘↑ ⌥⌘↓, Delete and ⌥⌘⌫ on the Mac). */
@Composable
private fun QueueActions(model: AppModel, index: Int) {
    val state by model.player.state.collectAsStateWithLifecycle()
    val entry = state.queue.getOrNull(index) ?: return
    val first = remember { FocusRequester() }
    val player = model.player
    fun done() { model.overlay = null }
    Panel(560.dp) {
        PanelTitle(entry.listName)
        OptionRow(stringResource(R.string.move_up), modifier = Modifier.focusRequester(first)) { player.move(index, index - 1); model.overlay = Overlay.QueueActions((index - 1).coerceAtLeast(0)) }
        OptionRow(stringResource(R.string.move_down)) { player.move(index, index + 1); model.overlay = Overlay.QueueActions((index + 1).coerceAtMost(state.queue.lastIndex)) }
        OptionRow(stringResource(R.string.remove)) { player.remove(index); done() }
        OptionRow(stringResource(R.string.clear_queue)) { player.clear(); done() }
    }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
}
