package pt.nunomartins.nuva.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.Overlay
import pt.nunomartins.nuva.R
import pt.nunomartins.nuva.audio.Audio
import pt.nunomartins.nuva.player.PlayMode
import pt.nunomartins.nuva.player.PlayerState

/** One device: the display and the keys on the left, the folders or the queue on the right. */
@Composable
fun PlayerScreen(model: AppModel) {
    val state by model.player.state.collectAsStateWithLifecycle()
    val playKey = remember { FocusRequester() }

    Row(
        Modifier.fillMaxSize().background(Tokens.surface0).padding(horizontal = 48.dp, vertical = 36.dp),
        horizontalArrangement = Arrangement.spacedBy(40.dp),
    ) {
        Column(Modifier.width(500.dp).fillMaxHeight()) {
            DisplayPanel(model, state)
            Spacer(Modifier.height(18.dp))
            Keys(model, state, playKey)
        }
        Column(Modifier.weight(1f).fillMaxHeight()) {
            Tabs(model)
            if (model.showingFolders) Folders(model, state) else Queue(model, state)
        }
    }
    LaunchedEffect(model.played) { runCatching { playKey.requestFocus() } }
}

/** The device's screen: always dark, recessed, the time in the mono's light weight. */
@Composable
fun DisplayPanel(model: AppModel, state: PlayerState, modifier: Modifier = Modifier) {
    val current = state.current
    val eq = Audio.equalizer
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Tokens.display).padding(horizontal = 24.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Led(state.isPlaying)
            Text(state.formatLabel.ifEmpty { current?.format.orEmpty() }, Type.displayMeta.copy(color = Tokens.displayMuted), Modifier.weight(1f))
            // The equalizer is a readout on the display that opens its controls, as on the Mac.
            Readout(onClick = { model.overlay = Overlay.Equalizer }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Led(eq.enabled, size = 6.dp)
                    Text("EQ · ${presetName(eq.preset)}", Type.displayMeta.copy(color = Tokens.displayMuted))
                }
            }
        }
        val failed = state.failedTitle
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            val cover = model.cover
            if (model.showArtwork && cover != null) {
                Image(remember(cover) { cover.asImageBitmap() }, null, Modifier.size(64.dp).clip(RoundedCornerShape(3.dp)), contentScale = ContentScale.Crop)
            }
            Column(Modifier.weight(1f)) {
                ScrollingText(
                    when {
                        failed != null -> stringResource(R.string.couldnt_play, failed)
                        current != null -> current.title
                        else -> stringResource(R.string.nothing_playing)
                    },
                    Type.title.copy(color = if (failed != null) Tokens.danger else Tokens.displayInk),
                )
                ScrollingText(current?.folderLine.orEmpty(), Type.body.copy(color = Tokens.displayMuted))
            }
        }
        Text(clock(state.position), Type.displayTime.copy(color = Tokens.displayInk))
        if (model.showSpectrum) {
            DisplaySpectrum(state.isPlaying)
            Spacer(Modifier.height(4.dp))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(clock(state.position), Type.displayMeta.copy(color = Tokens.displayMuted))
            PositionBar(if (state.duration > 0) (state.position / state.duration).toFloat() else 0f, Modifier.weight(1f))
            Text(clock(state.duration), Type.displayMeta.copy(color = Tokens.displayMuted))
        }
    }
}

/** A preset's name in the app's language; the Portuguese name is the key, as on the Mac. */
@Composable
fun presetName(key: String): String = when (key) {
    "Plano" -> stringResource(R.string.preset_flat)
    "Graves" -> stringResource(R.string.preset_bass)
    "Agudos" -> stringResource(R.string.preset_treble)
    "Voz" -> stringResource(R.string.preset_vocal)
    "Loudness" -> "Loudness"
    "Rock" -> "Rock"
    "Clássica" -> stringResource(R.string.preset_classical)
    "Noite" -> stringResource(R.string.preset_night)
    else -> stringResource(R.string.preset_custom)
}

/** Something on the display that opens its controls: no key face, only the focus ring. */
@Composable
private fun Readout(onClick: () -> Unit, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Box(
        Modifier
            .border(2.dp, if (focused) Tokens.focus else Color.Transparent, RoundedCornerShape(4.dp))
            .remoteClick(interaction, onClick, null)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) { content() }
}

/** The equalizer's 10 bands as columns of LED segments, as on the Mac's display. */
@Composable
private fun DisplaySpectrum(playing: Boolean) {
    val meter = remember { SpectrumMeter() }
    val time = meterFrames(playing)
    meter.update(time, if (playing) Audio.spectrum.levels(Audio.clock.now()) else null)
    val led = Tokens.led
    val ink = Tokens.displayInk
    val track = Tokens.displayTrack
    val segments = 12
    Canvas(Modifier.fillMaxWidth().height(44.dp)) {
        // Reading the frame's time makes this a new drawing each frame (the meter itself isn't observed).
        if (time < 0) return@Canvas
        val gap = 2.dp.toPx()
        val columnGap = 6.dp.toPx()
        val segment = (size.height - gap * (segments - 1)) / segments
        val width = (size.width - columnGap * 9) / 10
        for (c in 0 until 10) {
            val lit = kotlin.math.round(meter.levels[c] * segments).toInt()
            val peak = kotlin.math.round(meter.peaks[c] * segments).toInt() - 1
            for (s in 0 until segments) {
                val y = size.height - (s + 1) * (segment + gap) + gap
                val color = if (s < lit) led else if (s == peak && peak >= lit) ink else track
                drawRect(color, Offset(c * (width + columnGap), y), Size(width, segment))
            }
        }
    }
}

/** mode | playback | view, each group with its legend; the mode's legend is the mode itself. */
@Composable
private fun Keys(model: AppModel, state: PlayerState, playKey: FocusRequester) {
    val player = model.player
    val mode = state.mode
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
        // Wide enough for the longest mode's name, so the keys don't move when it changes.
        Group(modeName(mode), Modifier.width(104.dp)) {
            Key(Tone.Mode, 48.dp, { player.cycleMode() }, icon = modeIcon(mode), led = mode != PlayMode.Normal, description = stringResource(R.string.mode))
        }
        Group(stringResource(R.string.playback)) {
            Key(Tone.Transport, 56.dp, { player.previous() }, icon = Icons.previous, description = stringResource(R.string.previous))
            Key(
                Tone.Play, 84.dp, { player.playPause() }, Modifier.focusRequester(playKey),
                icon = if (state.isPlaying) Icons.pause else Icons.play, description = stringResource(R.string.play_pause),
            )
            Key(Tone.Transport, 56.dp, { player.next() }, icon = Icons.next, description = stringResource(R.string.next))
        }
        Group(stringResource(R.string.view)) {
            Key(Tone.Mode, 48.dp, { model.ambient = true }, icon = Icons.ambient, description = stringResource(R.string.ambient))
            Key(Tone.Mode, 48.dp, { model.overlay = Overlay.Settings }, icon = Icons.settings, description = stringResource(R.string.settings))
        }
    }
}

@Composable
private fun modeName(mode: PlayMode) = stringResource(
    when (mode) {
        PlayMode.Normal -> R.string.mode_normal
        PlayMode.Shuffle -> R.string.mode_shuffle
        PlayMode.RepeatAll -> R.string.mode_repeat_all
        PlayMode.RepeatOne -> R.string.mode_repeat_one
    },
)

private fun modeIcon(mode: PlayMode) = when (mode) {
    PlayMode.Normal -> Icons.inOrder
    PlayMode.Shuffle -> Icons.shuffle
    PlayMode.RepeatAll -> Icons.repeat
    PlayMode.RepeatOne -> Icons.repeatOne
}

@Composable
private fun Group(legend: String, modifier: Modifier = Modifier, keys: @Composable () -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) { keys() }
        Legend(legend, Modifier.padding(start = 4.dp))
    }
}

/** The right column's top: "queue" and "folders", each with its LED (lit: the one shown); OK on one shows it. Back from a list comes here. */
@Composable
private fun Tabs(model: AppModel) {
    val active = remember { FocusRequester() }
    LaunchedEffect(model.focusTabs) {
        if (model.focusTabs == 0) return@LaunchedEffect
        runCatching { active.requestFocus() }
    }
    Row(Modifier.fillMaxWidth().height(72.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        val queue = !model.showingFolders
        Tab(stringResource(R.string.queue), queue, if (queue) Modifier.focusRequester(active) else Modifier) { model.showingFolders = false }
        Tab(stringResource(R.string.folders), !queue, if (!queue) Modifier.focusRequester(active) else Modifier) { model.showingFolders = true }
    }
}

/** A tab: no key face, its LED and its name, and the focus ring. */
@Composable
private fun Tab(label: String, active: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Row(
        modifier
            .border(2.dp, if (focused) Tokens.focus else Color.Transparent, RoundedCornerShape(6.dp))
            .remoteClick(interaction, onClick, null)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Led(active, size = 6.dp)
        Text(label, Type.label.copy(color = if (active) Tokens.ink else Tokens.inkMuted, fontSize = Type.body.fontSize))
    }
}

@Composable
private fun ColumnScope.Folders(model: AppModel, state: PlayerState) {
    val entries = model.entries
    val tracks = entries.count { !it.isFolder }
    val list = rememberLazyListState()
    val row = remember { FocusRequester() }
    val target = entries.indexOfFirst { it.path == model.focusPath }.coerceAtLeast(0)
    // After going into or out of a folder, the focus stays in the list, on the row that makes sense.
    LaunchedEffect(model.focusList) {
        if (model.focusList == 0 || entries.isEmpty()) return@LaunchedEffect
        list.scrollToItem(target)
        withFrameNanos { }
        runCatching { row.requestFocus() }
    }
    // The browser's keys, as on the Mac: up and Play Folder, a note between them for a few seconds
    // ("12 tracks added"); the folder's name on its own line.
    val note = model.note
    if (model.path.isNotEmpty() || tracks > 0 || note != null) {
        Row(Modifier.fillMaxWidth().height(72.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (model.path.isNotEmpty()) Key(Tone.Mode, 48.dp, { model.up() }, icon = Icons.back, description = stringResource(R.string.up))
            Box(Modifier.weight(1f)) { if (note != null) Text(note, Type.hint.copy(color = Tokens.ink)) }
            if (tracks > 0) Key(Tone.Mode, 170.dp, { model.playFolder() }, text = stringResource(R.string.play_folder))
        }
    }
    if (model.path.isNotEmpty()) {
        ScrollingText(model.path.substringAfterLast('/'), Type.label.copy(color = Tokens.ink, fontSize = Type.body.fontSize), Modifier.padding(start = 16.dp, top = 4.dp))
    }
    Spacer(Modifier.height(8.dp))
    Box(Modifier.weight(1f).onFocusChanged { model.listFocused = it.hasFocus }) {
        when {
            model.error != null -> Text(model.error!!, Type.body.copy(color = Tokens.danger), maxLines = 3)
            model.loading && entries.isEmpty() -> Text(stringResource(R.string.loading), Type.body.copy(color = Tokens.inkMuted))
            entries.isEmpty() -> Text(stringResource(R.string.empty_folder), Type.body.copy(color = Tokens.inkMuted))
            else -> LazyColumn(state = list) {
                itemsIndexed(entries, key = { _, e -> e.path }) { index, entry ->
                    ListRow(
                        entry.listName,
                        if (entry.isFolder) null else entry.duration?.let(::minutes),
                        onClick = { if (entry.isFolder) model.open(entry) else model.playFolder(entry) },
                        modifier = if (index == target) Modifier.focusRequester(row) else Modifier,
                        isFolder = entry.isFolder,
                        playing = !entry.isFolder && state.current?.path == entry.path,
                        onLongClick = { model.enqueue(entry) },
                    )
                }
            }
        }
    }
    Legend(stringResource(R.string.hold_to_add), Modifier.padding(start = 16.dp, top = 8.dp))
}

@Composable
private fun ColumnScope.Queue(model: AppModel, state: PlayerState) {
    // The queue's length on its own line, as the folder's name is in the folders.
    if (state.queue.isNotEmpty()) {
        val total = state.queue.sumOf { it.duration ?: 0.0 }
        Text(
            pluralStringResource(R.plurals.tracks, state.queue.size, state.queue.size) + " · " + minutes(total),
            Type.duration.copy(color = Tokens.inkMuted), Modifier.padding(start = 16.dp, top = 4.dp),
        )
    }
    Spacer(Modifier.height(8.dp))
    if (state.queue.isEmpty()) {
        Text(stringResource(R.string.empty_queue), Type.body.copy(color = Tokens.inkMuted))
    } else {
        LazyColumn(Modifier.weight(1f).onFocusChanged { model.listFocused = it.hasFocus }) {
            itemsIndexed(state.queue) { index, entry ->
                ListRow(
                    entry.listName,
                    entry.duration?.let(::minutes),
                    onClick = { model.player.jump(index) },
                    playing = index == state.index,
                    onLongClick = { model.overlay = Overlay.QueueActions(index) },
                )
            }
        }
        Legend(stringResource(R.string.hold_for_more), Modifier.padding(start = 16.dp, top = 8.dp))
    }
}

/** A focus-aware background for panel rows: surface-2 with focus, as in the lists. */
@Composable
fun rowBackground(focused: Boolean) = animateColorAsState(if (focused) Tokens.surface2 else Color.Transparent, tween(120), label = "row").value
