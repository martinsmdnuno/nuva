package pt.nunomartins.nuva.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import pt.nunomartins.nuva.library.Entry

/** What the display and the keys show. */
data class PlayerState(
    val queue: List<Entry> = emptyList(),
    val index: Int = -1,
    val isPlaying: Boolean = false,
    val position: Double = 0.0,
    val duration: Double = 0.0,
    /** "FLAC 24/96", from the decoder's own format. */
    val formatLabel: String = "",
    val shuffle: Boolean = false,
    val repeat: Int = Player.REPEAT_MODE_OFF,
    /** The title that couldn't play, shown on the display until a track plays. */
    val failedTitle: String? = null,
) {
    val current: Entry? get() = queue.getOrNull(index)
}

/** Talks to the playback service. The queue is a folder (or the part of it from a track on). */
class PlayerModel(context: Context) {
    private val _state = MutableStateFlow(PlayerState())
    val state: StateFlow<PlayerState> = _state.asStateFlow()
    private var controller: MediaController? = null
    private var entries: List<Entry> = emptyList()
    private var pending: (() -> Unit)? = null

    init {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            controller = future.get().also { it.addListener(listener) }
            pending?.invoke()
            pending = null
            refresh()
        }, MoreExecutors.directExecutor())
    }

    /** Plays `tracks` from `start`. `urls` are the original files' streams. */
    fun play(tracks: List<Entry>, urls: List<String>, start: Int) {
        val action = {
            val c = controller!!
            entries = tracks
            val items = tracks.zip(urls).map { (entry, url) ->
                MediaItem.Builder()
                    .setMediaId(entry.path)
                    .setUri(url)
                    .setMediaMetadata(
                        MediaMetadata.Builder()
                            .setTitle(entry.title)
                            .setAlbumTitle(entry.folderName)
                            .setIsPlayable(true)
                            .build(),
                    )
                    .build()
            }
            c.setMediaItems(items, start, 0)
            c.prepare()
            c.play()
            _state.update { it.copy(failedTitle = null) }
        }
        if (controller != null) action() else pending = action
    }

    fun playPause() = controller?.run { if (isPlaying) pause() else { if (playbackState == Player.STATE_IDLE) prepare(); play() } }
    fun next() = controller?.seekToNextMediaItem()
    fun previous() = controller?.seekToPrevious()
    fun jump(index: Int) = controller?.run { seekTo(index, 0); play() }
    fun skip(seconds: Int) = controller?.run { seekTo((currentPosition + seconds * 1000L).coerceAtLeast(0)) }
    fun toggleShuffle() = controller?.run { shuffleModeEnabled = !shuffleModeEnabled }

    /** Off → all → one → off, as on the Mac. */
    fun cycleRepeat() = controller?.run {
        repeatMode = when (repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    /** Called by the display a few times a second for the time and the bar. */
    fun refresh() {
        val c = controller ?: return
        _state.update {
            it.copy(
                queue = entries,
                index = if (entries.isEmpty()) -1 else c.currentMediaItemIndex,
                isPlaying = c.isPlaying,
                position = c.currentPosition.coerceAtLeast(0) / 1000.0,
                duration = if (c.duration == C.TIME_UNSET) it.current?.duration ?: 0.0 else c.duration / 1000.0,
                shuffle = c.shuffleModeEnabled,
                repeat = c.repeatMode,
            )
        }
    }

    fun release() {
        controller?.release()
        controller = null
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) = refresh()

        override fun onTracksChanged(tracks: Tracks) {
            val format = tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_AUDIO && it.isSelected }?.getTrackFormat(0)
            _state.update { it.copy(formatLabel = format?.let(::label) ?: it.current?.format.orEmpty()) }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            _state.update { it.copy(failedTitle = null) }
        }

        override fun onPlayerError(error: PlaybackException) {
            // Show which track couldn't play and go on with the next, as the Mac does.
            val c = controller ?: return
            _state.update { it.copy(failedTitle = it.current?.title) }
            if (c.hasNextMediaItem()) {
                c.seekToNextMediaItem()
                c.prepare()
                c.play()
            }
        }
    }

    companion object {
        /** "FLAC 24/96", "FLAC 16/44.1", or just the codec when the bit depth isn't known. */
        fun label(format: Format): String {
            val codec = when (format.sampleMimeType) {
                "audio/flac" -> "FLAC"
                "audio/mpeg" -> "MP3"
                "audio/mp4a-latm" -> "AAC"
                "audio/alac" -> "ALAC"
                "audio/raw" -> "PCM"
                else -> format.sampleMimeType?.substringAfter('/')?.uppercase() ?: ""
            }
            val bits = when (format.pcmEncoding) {
                C.ENCODING_PCM_16BIT -> 16
                C.ENCODING_PCM_24BIT -> 24
                C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> 32
                else -> null
            }
            val rate = format.sampleRate.takeIf { it > 0 }?.let { r ->
                val k = r / 1000.0
                if (k % 1.0 == 0.0) k.toInt().toString() else "%.1f".format(java.util.Locale.ROOT, k)
            }
            return when {
                bits != null && rate != null -> "$codec $bits/$rate"
                rate != null -> "$codec · $rate kHz"
                else -> codec
            }
        }
    }
}
