package pt.nunomartins.nuva.player

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import pt.nunomartins.nuva.library.Entry
import java.io.ByteArrayOutputStream

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
    val mode: PlayMode get() = PlayMode.of(shuffle, repeat)
}

/** Talks to the playback service. The queue lives in the player; entries are kept here by their path. */
@OptIn(UnstableApi::class)
class PlayerModel(context: Context) {
    private val _state = MutableStateFlow(PlayerState())
    val state: StateFlow<PlayerState> = _state.asStateFlow()
    private var controller: MediaController? = null
    private val known = mutableMapOf<String, Entry>()
    private val pending = mutableListOf<() -> Unit>()

    init {
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            controller = future.get().also { it.addListener(listener) }
            pending.forEach { it() }
            pending.clear()
            refresh()
        }, MoreExecutors.directExecutor())
    }

    private fun whenReady(action: (MediaController) -> Unit) {
        val c = controller
        if (c != null) action(c) else pending += { action(controller!!) }
    }

    private fun item(entry: Entry, url: String): MediaItem {
        known[entry.path] = entry
        return MediaItem.Builder()
            .setMediaId(entry.path)
            .setUri(url)
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(entry.title).setArtist(entry.artistFolder)
                    .setAlbumTitle(entry.albumPath.substringAfterLast('/')).setIsPlayable(true).build(),
            )
            .build()
    }

    /** Replaces the queue with `tracks` and plays from `start`. `urls` are the original files' streams. */
    fun play(tracks: List<Entry>, urls: List<String>, start: Int, positionMs: Long = 0, autoplay: Boolean = true) = whenReady { c ->
        c.setMediaItems(tracks.zip(urls).map { (e, u) -> item(e, u) }, start, positionMs)
        c.prepare()
        if (autoplay) c.play()
        _state.update { it.copy(failedTitle = null) }
    }

    /** Adds to the end of the queue, as ⌘Enter does on the Mac; starts playing if nothing was. */
    fun append(tracks: List<Entry>, urls: List<String>) = whenReady { c ->
        val wasEmpty = c.mediaItemCount == 0
        c.addMediaItems(tracks.zip(urls).map { (e, u) -> item(e, u) })
        if (wasEmpty) {
            c.prepare()
            c.play()
        }
    }

    fun remove(index: Int) = whenReady { it.removeMediaItem(index) }
    fun move(from: Int, to: Int) = whenReady { if (to in 0 until it.mediaItemCount) it.moveMediaItem(from, to) }
    fun clear() = whenReady { it.clearMediaItems() }

    fun playPause() = whenReady { c -> if (c.isPlaying) c.pause() else { if (c.playbackState == Player.STATE_IDLE) c.prepare(); c.play() } }
    fun next() = whenReady { it.seekToNextMediaItem() }
    fun previous() = whenReady { it.seekToPrevious() }
    fun jump(index: Int) = whenReady { it.seekTo(index, 0); it.play() }
    fun skip(seconds: Int) = whenReady { it.seekTo((it.currentPosition + seconds * 1000L).coerceAtLeast(0)) }
    /** The mode key: normal → shuffle → repeat all → repeat one → normal. */
    fun cycleMode() = whenReady {
        val mode = PlayMode.of(it.shuffleModeEnabled, it.repeatMode).next
        it.shuffleModeEnabled = mode.shuffle
        it.repeatMode = mode.repeat
    }

    /** The cover for Now Playing (the TV's media controls and the remote's screen). */
    fun setArtwork(path: String, cover: Bitmap?) = whenReady { c ->
        val index = (0 until c.mediaItemCount).firstOrNull { c.getMediaItemAt(it).mediaId == path } ?: return@whenReady
        val old = c.getMediaItemAt(index)
        val bytes = cover?.let { b -> ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray() }
        val metadata = old.mediaMetadata.buildUpon().setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER).build()
        c.replaceMediaItem(index, old.buildUpon().setMediaMetadata(metadata).build())
    }

    /** Something is already in the player (the app was reopened while it played). */
    val hasQueue: Boolean get() = (controller?.mediaItemCount ?: 0) > 0

    /** Runs `action` once the player is reachable. */
    fun ready(action: () -> Unit) = whenReady { action() }

    /** Called by the display a few times a second for the time and the bar. */
    fun refresh() {
        val c = controller ?: return
        val queue = (0 until c.mediaItemCount).mapNotNull { known[c.getMediaItemAt(it).mediaId] }
        _state.update {
            it.copy(
                queue = queue,
                index = if (queue.isEmpty()) -1 else c.currentMediaItemIndex,
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
