package pt.nunomartins.nuva.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.withFrameNanos
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.Player
import pt.nunomartins.nuva.AppModel
import pt.nunomartins.nuva.R
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
            DisplayPanel(state)
            Spacer(Modifier.height(28.dp))
            Keys(model, state, playKey)
        }
        Column(Modifier.weight(1f).fillMaxHeight()) {
            if (model.showingFolders) Folders(model, state) else Queue(model, state)
        }
    }
    LaunchedEffect(model.played) { runCatching { playKey.requestFocus() } }
}

/** The device's screen: always dark, recessed, the time in Plex Mono Light. */
@Composable
fun DisplayPanel(state: PlayerState, modifier: Modifier = Modifier) {
    val current = state.current
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(Tokens.display).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Led(state.isPlaying)
            Text(state.formatLabel.ifEmpty { current?.format.orEmpty() }, Type.displayMeta.copy(color = Tokens.displayMuted))
        }
        val failed = state.failedTitle
        Text(
            when {
                failed != null -> stringResource(R.string.couldnt_play, failed)
                current != null -> current.title
                else -> stringResource(R.string.nothing_playing)
            },
            Type.title.copy(color = if (failed != null) Tokens.danger else Tokens.displayInk),
        )
        Text(current?.folderName.orEmpty(), Type.body.copy(color = Tokens.displayMuted))
        Spacer(Modifier.height(8.dp))
        Text(clock(state.position), Type.displayTime.copy(color = Tokens.displayInk))
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(clock(state.position), Type.displayMeta.copy(color = Tokens.displayMuted))
            PositionBar(if (state.duration > 0) (state.position / state.duration).toFloat() else 0f, Modifier.weight(1f))
            Text(clock(state.duration), Type.displayMeta.copy(color = Tokens.displayMuted))
        }
    }
}

/** mode | playback | view, each group with its legend; play on the group's centre. */
@Composable
private fun Keys(model: AppModel, state: PlayerState, playKey: FocusRequester) {
    val player = model.player
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Bottom) {
        Group(stringResource(R.string.mode)) {
            Key(Tone.Mode, 48.dp, { player.toggleShuffle() }, icon = Icons.shuffle, led = state.shuffle, description = stringResource(R.string.shuffle))
            Key(Tone.Mode, 48.dp, { player.cycleRepeat() }, icon = Icons.repeat, led = state.repeat != Player.REPEAT_MODE_OFF, description = stringResource(R.string.repeat))
        }
        Group(stringResource(R.string.playback)) {
            Key(Tone.Transport, 56.dp, { player.previous() }, icon = Icons.previous, led = null, description = stringResource(R.string.previous))
            Key(
                Tone.Play, 84.dp, { player.playPause() }, Modifier.focusRequester(playKey),
                icon = if (state.isPlaying) Icons.pause else Icons.play, description = stringResource(R.string.play_pause),
            )
            Key(Tone.Transport, 56.dp, { player.next() }, icon = Icons.next, description = stringResource(R.string.next))
        }
        Group(stringResource(R.string.view)) {
            Key(Tone.Mode, 48.dp, { model.showingFolders = !model.showingFolders }, icon = Icons.folders, led = model.showingFolders, description = stringResource(R.string.folders))
            Key(Tone.Mode, 48.dp, { model.ambient = true }, icon = Icons.ambient, description = stringResource(R.string.ambient))
        }
    }
}

@Composable
private fun Group(legend: String, keys: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) { keys() }
        Legend(legend, Modifier.padding(start = 4.dp))
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
    // The browser's keys on the header row, as on the Mac; the folder's name on its own line.
    Row(Modifier.fillMaxWidth().height(80.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (model.path.isNotEmpty()) Key(Tone.Mode, 48.dp, { model.up() }, icon = Icons.back, description = stringResource(R.string.up))
        Legend(stringResource(R.string.folders), Modifier.weight(1f))
        if (tracks > 0) Key(Tone.Mode, 170.dp, { model.playFolder() }, text = stringResource(R.string.play_folder))
    }
    if (model.path.isNotEmpty()) {
        Text(model.path.substringAfterLast('/'), Type.label.copy(color = Tokens.ink, fontSize = Type.body.fontSize), Modifier.padding(start = 16.dp, top = 4.dp))
    }
    Spacer(Modifier.height(8.dp))
    Box(Modifier.weight(1f)) {
        when {
            model.error != null -> Text(model.error!!, Type.body.copy(color = Tokens.danger), maxLines = 3)
            model.loading && entries.isEmpty() -> Text(stringResource(R.string.loading), Type.body.copy(color = Tokens.inkMuted))
            entries.isEmpty() -> Text(stringResource(R.string.empty_folder), Type.body.copy(color = Tokens.inkMuted))
            else -> LazyColumn(state = list) {
                itemsIndexed(entries, key = { _, e -> e.path }) { index, entry ->
                    val playing = !entry.isFolder && state.current?.path == entry.path
                    ListRow(
                        entry.listName,
                        if (entry.isFolder) null else entry.duration?.let(::minutes),
                        onClick = { if (entry.isFolder) model.open(entry) else model.playFolder(entry) },
                        modifier = if (index == target) Modifier.focusRequester(row) else Modifier,
                        isFolder = entry.isFolder,
                        playing = playing,
                    )
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.Queue(model: AppModel, state: PlayerState) {
    val total = state.queue.sumOf { it.duration ?: 0.0 }
    Row(Modifier.fillMaxWidth().height(80.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Led(state.queue.isNotEmpty())
        Text(stringResource(R.string.queue), Type.label.copy(color = Tokens.ink, fontSize = Type.body.fontSize))
        if (state.queue.isNotEmpty()) {
            Text(
                pluralStringResource(R.plurals.tracks, state.queue.size, state.queue.size) + " · " + minutes(total),
                Type.duration.copy(color = Tokens.inkMuted),
            )
        }
    }
    Spacer(Modifier.height(8.dp))
    if (state.queue.isEmpty()) {
        Text(stringResource(R.string.empty_queue), Type.body.copy(color = Tokens.inkMuted))
    } else {
        LazyColumn(Modifier.weight(1f)) {
            itemsIndexed(state.queue) { index, entry ->
                ListRow(
                    entry.listName,
                    entry.duration?.let(::minutes),
                    onClick = { model.player.jump(index) },
                    playing = index == state.index,
                )
            }
        }
    }
}
