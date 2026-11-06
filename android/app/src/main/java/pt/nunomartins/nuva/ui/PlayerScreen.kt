package pt.nunomartins.nuva.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.TextUnit
import kotlinx.coroutines.delay
import kotlin.math.roundToInt
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.Overlay
import pt.nunomartins.nuva.R
import pt.nunomartins.nuva.audio.Audio
import pt.nunomartins.nuva.player.PlayMode
import pt.nunomartins.nuva.player.PlayerState

/**
 * The folders, the whole screen: the menu key at the top, the list, and at the foot, while something
 * plays, the "now playing" bar (OK on it opens the player).
 */
@Composable
fun BrowserScreen(model: AppModel) {
    val state by model.player.state.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().background(Tokens.surface0).padding(horizontal = 64.dp, vertical = 32.dp)) {
        Row(Modifier.fillMaxWidth().height(56.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.app_name), Type.title.copy(color = Tokens.ink))
            Spacer(Modifier.weight(1f))
            Key(Tone.Mode, 56.dp, { model.overlay = Overlay.Menu }, icon = Icons.menu, description = stringResource(R.string.menu), height = 48.dp)
        }
        Folders(model, state)
        if (state.current != null) NowPlayingBar(model, state)
    }
}

/** The track playing, at the foot of the folders: LED, cover, title and folders, time. OK opens the player. */
@Composable
private fun NowPlayingBar(model: AppModel, state: PlayerState) {
    val entry = state.current ?: return
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier.padding(top = 16.dp).fillMaxWidth().height(76.dp)
            .border(2.dp, if (focused) Tokens.focus else Color.Transparent, shape)
            .padding(3.dp).clip(shape).background(Tokens.display)
            .remoteClick(interaction, { model.nowPlaying = true }, null)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Led(state.isPlaying)
        val cover = model.cover
        if (model.showArtwork && cover != null) {
            Image(remember(cover) { cover.asImageBitmap() }, null, Modifier.size(48.dp).clip(RoundedCornerShape(3.dp)), contentScale = ContentScale.Crop)
        }
        Column(Modifier.weight(1f)) {
            ScrollingText(entry.title, Type.label.copy(color = Tokens.displayInk, fontSize = Type.body.fontSize), moving = focused)
            ScrollingText(entry.folderLine, Type.duration.copy(color = Tokens.displayMuted), moving = focused)
        }
        Text("${clock(state.shownPosition)} / ${clock(state.duration)}", Type.displayMeta.copy(color = Tokens.displayMuted))
    }
}

/**
 * The player, the whole screen, on the display's colour with the cover's glow moving behind. Top: back
 * to the folders, LED, quality and the source. Middle: the cover, and beside it a column whose top is
 * the cover's top (title, then artist and album, both sliding when too long) and whose foot is the
 * cover's foot (the time), all on one left edge. Then the bar, and the keys: mode on the left,
 * previous · play · next centred on the time, ambient and the menu on the right.
 */
@Composable
fun PlayerScreen(model: AppModel) {
    val state by model.player.state.collectAsStateWithLifecycle()
    val player = model.player
    val entry = state.current
    val playKey = remember { FocusRequester() }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }
    val density = LocalDensity.current
    fun sp(dp: Dp): TextUnit = with(density) { dp.toSp() }

    BoxWithConstraints(Modifier.fillMaxSize().background(Tokens.display)) {
        GlowBackground(model, state.isPlaying, strong = true, opacity = 1f, now = now)
        val u = maxWidth / 100
        val coverSize = maxHeight * 0.46f
        // Where the time's centre is, so previous · play · next sit under it.
        var timeCentre by remember { mutableFloatStateOf(Float.NaN) }
        var keysLeft by remember { mutableFloatStateOf(0f) }
        var transportWidth by remember { mutableIntStateOf(0) }
        // The side groups' inner edges: previous · play · next never go over them.
        var modeRight by remember { mutableFloatStateOf(0f) }
        var endLeft by remember { mutableFloatStateOf(Float.NaN) }
        val clearance = with(density) { 32.dp.toPx() }

        Column(Modifier.fillMaxSize().padding(start = u * 8, end = u * 8, top = u * 3f, bottom = u * 3.5f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(u * 1.4f)) {
                Key(Tone.Mode, 56.dp, { model.nowPlaying = false }, icon = Icons.back, description = stringResource(R.string.folders), height = 44.dp)
                Led(state.isPlaying, size = u * 0.8f)
                Box(Modifier.weight(1f)) {
                    QualityBadge(state, Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.5f)), u * 1.2f, u * 0.45f)
                }
                Text(stringResource(R.string.source_server), Type.displayMeta.copy(color = Tokens.displayMuted, fontSize = sp(u * 1.7f)))
            }
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth().height(coverSize), horizontalArrangement = Arrangement.spacedBy(u * 5)) {
                val cover = model.cover
                if (model.showArtwork && cover != null) {
                    Image(remember(cover) { cover.asImageBitmap() }, null, Modifier.size(coverSize).clip(RoundedCornerShape(4.dp)), contentScale = ContentScale.Crop)
                }
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    val failed = state.failedTitle
                    ScrollingText(
                        when {
                            failed != null -> stringResource(R.string.couldnt_play, failed)
                            entry != null -> entry.title
                            else -> stringResource(R.string.nothing_playing)
                        },
                        Type.title.copy(
                            color = if (failed != null) Tokens.danger else if (entry == null) Tokens.displayMuted else Tokens.displayInk,
                            fontSize = sp(u * 4.6f), lineHeight = sp(u * 5.2f),
                        ),
                        // Up by the font's room above the capitals: the title's top is the cover's top.
                        Modifier.offset(y = -u * 1.05f),
                    )
                    Spacer(Modifier.height(u * 1.2f))
                    ScrollingText(
                        entry?.folderLine ?: stringResource(R.string.choose_folder),
                        Type.body.copy(color = Tokens.displayMuted, fontSize = sp(u * 2.4f), lineHeight = sp(u * 3f)),
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        clock(state.shownPosition),
                        Type.displayTime.copy(color = Tokens.displayInk, fontSize = sp(u * 5.9f), lineHeight = sp(u * 5.9f)),
                        // Down by the room under the digits: their foot is the cover's foot.
                        Modifier.offset(y = u * 1.45f).onGloballyPositioned { timeCentre = it.boundsInRoot().center.x },
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            ScrubRow(model, state)
            Spacer(Modifier.height(u * 1.6f))
            Box(Modifier.fillMaxWidth().onGloballyPositioned { keysLeft = it.boundsInRoot().left }) {
                Row(
                    Modifier.align(Alignment.CenterStart).onGloballyPositioned { modeRight = it.boundsInRoot().right },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Key(Tone.Mode, 56.dp, { player.cycleMode() }, icon = modeIcon(state.mode), description = stringResource(R.string.mode))
                    Text(modeName(state.mode).lowercase(), Type.legend.copy(color = Tokens.displayMuted))
                }
                Row(
                    Modifier.align(Alignment.CenterStart)
                        .onSizeChanged { transportWidth = it.width }
                        .offset {
                            val lowest = modeRight - keysLeft + clearance
                            val highest = if (endLeft.isNaN()) Float.MAX_VALUE else endLeft - keysLeft - transportWidth - clearance
                            val wanted = if (timeCentre.isNaN()) lowest else timeCentre - keysLeft - transportWidth / 2f
                            IntOffset(wanted.coerceAtMost(highest).coerceAtLeast(lowest).roundToInt(), 0)
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Key(Tone.Transport, 56.dp, { player.previous() }, icon = Icons.previous, description = stringResource(R.string.previous))
                    Key(
                        Tone.Play, 84.dp, { player.playPause() }, Modifier.focusRequester(playKey),
                        icon = if (state.isPlaying) Icons.pause else Icons.play, description = stringResource(R.string.play_pause),
                    )
                    Key(Tone.Transport, 56.dp, { player.next() }, icon = Icons.next, description = stringResource(R.string.next))
                }
                Row(Modifier.align(Alignment.CenterEnd).onGloballyPositioned { endLeft = it.boundsInRoot().left }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Key(Tone.Mode, 56.dp, { model.ambient = true }, icon = Icons.ambient, description = stringResource(R.string.ambient))
                    Key(Tone.Mode, 56.dp, { model.overlay = Overlay.Menu }, icon = Icons.menu, description = stringResource(R.string.menu))
                }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { playKey.requestFocus() } }
}

/**
 * The time and the bar, which take the focus: OK holds the bar, then ← → move 10 s a press (faster
 * held) and the track goes there when the key is let go; OK keeps it, Back goes back to where it was.
 * Held, the elapsed time lights and the bar thickens.
 */
@Composable
private fun ScrubRow(model: AppModel, state: PlayerState) {
    val player = model.player
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val scrubbing = state.scrub != null
    LaunchedEffect(focused) { if (!focused && player.scrubbing) player.endScrub(keep = true) }
    Row(
        Modifier
            .bleed(8.dp)
            .border(2.dp, if (focused) Tokens.focus else Color.Transparent, RoundedCornerShape(4.dp))
            .onPreviewKeyEvent { e ->
                val ok = e.key == Key.DirectionCenter || e.key == Key.Enter || e.key == Key.NumPadEnter
                val side = when (e.key) { Key.DirectionLeft -> -1; Key.DirectionRight -> 1; else -> 0 }
                when (e.type) {
                    KeyEventType.KeyDown -> when {
                        ok -> true
                        player.scrubbing && side != 0 -> { player.scrubStep(side, e.nativeKeyEvent.repeatCount); true }
                        else -> false
                    }
                    KeyEventType.KeyUp -> when {
                        ok -> { if (player.scrubbing) player.endScrub(keep = true) else player.startScrub(); true }
                        player.scrubbing && side != 0 -> { player.scrubSeek(); true }
                        else -> false
                    }
                    else -> false
                }
            }
            .focusable(interactionSource = interaction)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        val shown = state.shownPosition
        Text(clock(shown), Type.displayMeta.copy(color = if (scrubbing) Tokens.displayInk else Tokens.displayMuted))
        PositionBar(if (state.duration > 0) (shown / state.duration).toFloat() else 0f, Modifier.weight(1f), height = if (scrubbing) 8.dp else 4.dp)
        Text(clock(state.duration), Type.displayMeta.copy(color = Tokens.displayMuted))
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
        Row(Modifier.fillMaxWidth().height(64.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (model.path.isNotEmpty()) Key(Tone.Mode, 48.dp, { model.up() }, icon = Icons.back, description = stringResource(R.string.up))
            Box(Modifier.weight(1f)) { if (note != null) Text(note, Type.hint.copy(color = Tokens.ink)) }
            if (tracks > 0) Key(Tone.Mode, 170.dp, { model.playFolder() }, text = stringResource(R.string.play_folder))
        }
    }
    if (model.path.isNotEmpty()) {
        ScrollingText(model.path.substringAfterLast('/'), Type.label.copy(color = Tokens.ink, fontSize = Type.body.fontSize), Modifier.padding(start = 16.dp, top = 4.dp))
    }
    Spacer(Modifier.height(8.dp))
    Box(Modifier.weight(1f)) {
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

/** The queue, in the menu's panel: the playing track has the focus. */
@Composable
fun ColumnScope.Queue(model: AppModel, state: PlayerState) {
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
        val list = rememberLazyListState()
        val playing = remember { FocusRequester() }
        val start = state.index.coerceIn(0, state.queue.lastIndex)
        LaunchedEffect(Unit) {
            list.scrollToItem(start)
            withFrameNanos { }
            runCatching { playing.requestFocus() }
        }
        LazyColumn(Modifier.weight(1f), state = list) {
            itemsIndexed(state.queue) { index, entry ->
                ListRow(
                    entry.listName,
                    entry.duration?.let(::minutes),
                    onClick = { model.player.jump(index) },
                    modifier = if (index == start) Modifier.focusRequester(playing) else Modifier,
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
