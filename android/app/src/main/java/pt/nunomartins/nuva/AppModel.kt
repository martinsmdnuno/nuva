package pt.nunomartins.nuva

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import pt.nunomartins.nuva.artwork.ArtworkGlow
import pt.nunomartins.nuva.artwork.GlowField
import pt.nunomartins.nuva.artwork.ArtworkOrigin
import pt.nunomartins.nuva.artwork.ArtworkResolver
import pt.nunomartins.nuva.artwork.CoverArtArchive
import pt.nunomartins.nuva.library.Account
import pt.nunomartins.nuva.library.Entry
import pt.nunomartins.nuva.library.JellyfinSource
import pt.nunomartins.nuva.library.SourceException
import pt.nunomartins.nuva.player.PlayerModel
import pt.nunomartins.nuva.player.PlayerState
import pt.nunomartins.nuva.ui.Look
import pt.nunomartins.nuva.ui.Tokens
import java.io.File

/** What sits over the player: a panel, or a question. */
sealed interface Overlay {
    data object Equalizer : Overlay
    data object Settings : Overlay
    data object Terms : Overlay
    data object ConfirmExit : Overlay
    /** The player's menu: queue, equalizer and settings. */
    data object Menu : Overlay
    /** The queue, from the player's menu. */
    data object Queue : Overlay
    /** Move, remove or clear, for the queue row at `index` (holding OK on it). */
    data class QueueActions(val index: Int) : Overlay
}

/** The app's state: the account, the folder being browsed, the player and the options. */
class AppModel(app: Application) : AndroidViewModel(app) {
    private val account = Account(app)
    private val prefs = app.getSharedPreferences("options", Context.MODE_PRIVATE)
    val player = PlayerModel(app)
    val updates = Updates(app, VERSION)
    private var source: JellyfinSource? = account.server?.let { server -> account.session?.let { open(server, it) } }
    private val artwork = ArtworkResolver(File(app.filesDir, "artwork"), CoverArtArchive(VERSION)) { folder -> source?.folderArtwork(folder) }

    var signedIn by mutableStateOf(source != null)
        private set
    val savedServer: String get() = account.server.orEmpty()
    val savedUser: String get() = account.username.orEmpty()

    var path by mutableStateOf("")
        private set
    var entries by mutableStateOf<List<Entry>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    /** A short note on the header ("12 tracks added"), gone after a few seconds. */
    var note by mutableStateOf<String?>(null)
        private set
    /** Folders or the queue on the right, as ⌘B swaps them on the Mac; the tabs choose. */
    /** The player screen is showing (playing a folder opens it; Back goes to the folders). */
    var nowPlaying by mutableStateOf(false)
    var ambient by mutableStateOf(false)
    var overlay by mutableStateOf<Overlay?>(null)

    /** After moving between folders, the row the remote's focus goes to (null: the first). */
    var focusPath by mutableStateOf<String?>(null)
        private set
    /** Bumped when the list should take the focus, and when a folder starts playing (the play key takes it). */
    var focusList by mutableIntStateOf(0)
        private set
    var played by mutableIntStateOf(0)
        private set
    // Options, as in the Mac's View menu.
    var showArtwork by mutableStateOf(prefs.getBoolean("artwork", false))
        private set
    var showSpectrum by mutableStateOf(prefs.getBoolean("spectrum", true))
        private set
    /** A minute untouched while music plays: the screen becomes the display. */
    var autoAmbient by mutableStateOf(prefs.getBoolean("autoAmbient", true))
        private set

    /** The playing album's cover (with artwork on), and its glow for ambient mode. */
    var cover by mutableStateOf<Bitmap?>(null)
        private set
    var glow by mutableStateOf<GlowField?>(null)
        private set
    /** Where the playing album's cover came from, or why there is none (null: not looked up). */
    var artworkOrigin by mutableStateOf<ArtworkOrigin?>(null)
        private set
    private var coverFor: String? = null
    private var coverJob: Job? = null
    private var glowSkin: String? = null

    init {
        if (signedIn) {
            load(prefs.getString("folder", "") ?: "")
            resume()
        }
        updates.checkDaily(viewModelScope)
    }

    fun checkUpdates() = updates.check(viewModelScope)

    fun toggleShowArtwork() {
        val on = !showArtwork
        showArtwork = on
        prefs.edit().putBoolean("artwork", on).apply()
        coverFor = null
        if (!on) {
            cover = null
            glow = null
            artworkOrigin = null
        }
    }

    fun toggleShowSpectrum() {
        val on = !showSpectrum
        showSpectrum = on
        prefs.edit().putBoolean("spectrum", on).apply()
    }

    fun toggleAutoAmbient() {
        val on = !autoAmbient
        autoAmbient = on
        prefs.edit().putBoolean("autoAmbient", on).apply()
    }

    fun signIn(server: String, user: String, password: String) {
        val address = JellyfinSource.normalise(server)
        loading = true
        error = null
        viewModelScope.launch {
            try {
                val session = JellyfinSource.login(address, user.trim(), password, account.deviceId, VERSION)
                account.save(address, user.trim(), session)
                source = open(address, session)
                signedIn = true
                load("")
            } catch (e: SourceException) {
                error = message(e)
            } finally {
                loading = false
            }
        }
    }

    fun signOut() {
        account.signOut()
        source = null
        signedIn = false
        entries = emptyList()
        path = ""
        overlay = null
        player.clear()
    }

    fun open(folder: Entry) = load(folder.path, focus = null)

    /** Goes up a level, with the focus on the folder just left. */
    fun up() = load(path.substringBeforeLast('/', ""), focus = path)

    /** Plays the folder being browsed from `track` (or the top), and opens the player. */
    fun playFolder(track: Entry? = null) {
        val source = source ?: return
        val tracks = entries.filter { !it.isFolder }
        if (tracks.isEmpty()) return
        viewModelScope.launch {
            try {
                val urls = tracks.map { source.url(it) }
                player.play(tracks, urls, track?.let { tracks.indexOf(it) }?.coerceAtLeast(0) ?: 0)
                nowPlaying = true
                played++
            } catch (e: SourceException) {
                error = message(e)
            }
        }
    }

    /** Holding OK on a folder or a track: adds it to the end of the queue (⌘Enter on the Mac). */
    fun enqueue(entry: Entry) {
        val source = source ?: return
        viewModelScope.launch {
            try {
                val tracks = if (entry.isFolder) source.list(entry.path).filter { !it.isFolder } else listOf(entry)
                if (tracks.isEmpty()) return@launch
                player.append(tracks, tracks.map { source.url(it) })
                val res = getApplication<Application>().resources
                say(res.getQuantityString(R.plurals.added, tracks.size, tracks.size))
            } catch (e: SourceException) {
                error = message(e)
            }
        }
    }

    private fun say(text: String) {
        note = text
        viewModelScope.launch {
            delay(3000)
            if (note == text) note = null
        }
    }

    private fun load(folder: String, focus: String? = null) {
        val source = source ?: return
        loading = true
        error = null
        viewModelScope.launch {
            try {
                entries = source.list(folder)
                path = folder
                prefs.edit().putString("folder", folder).apply()
                focusPath = focus
                focusList++
            } catch (e: SourceException) {
                if (e.reason == SourceException.Reason.LoginFailed) signOut()
                // A folder that's gone: back to the top.
                if (e.reason == SourceException.Reason.MissingFolder && folder.isNotEmpty()) return@launch load("")
                error = message(e)
            } finally {
                loading = false
            }
        }
    }

    // MARK: The last session

    private var lastSaved = 0L
    private var lastIndex = -2

    /** Called a few times a second: remembers the queue and the place in it, and follows the cover. */
    fun tick(state: PlayerState) {
        val now = System.currentTimeMillis()
        if (state.queue.isNotEmpty() && (state.index != lastIndex || now - lastSaved > 5000)) {
            lastIndex = state.index
            lastSaved = now
            val tracks = JSONArray()
            state.queue.forEach { tracks.put(JSONObject().put("path", it.path).put("name", it.name).put("duration", it.duration ?: -1.0).put("size", it.size ?: -1L)) }
            prefs.edit().putString("session", JSONObject()
                .put("tracks", tracks).put("index", state.index).put("position", (state.position * 1000).toLong()).toString()).apply()
        }
        followCover(state.current)
    }

    /** Reopening the app: the last queue comes back, paused where it was, unless something is already playing. */
    private fun resume() {
        val saved = prefs.getString("session", null) ?: return
        player.ready {
            if (player.hasQueue) return@ready
            val source = source ?: return@ready
            viewModelScope.launch {
                try {
                    val json = JSONObject(saved)
                    val list = json.getJSONArray("tracks")
                    val tracks = (0 until list.length()).map {
                        val t = list.getJSONObject(it)
                        Entry(t.getString("path"), t.getString("name"), false, t.getDouble("duration").takeIf { d -> d >= 0 }, t.optLong("size", -1).takeIf { b -> b > 0 })
                    }
                    if (tracks.isEmpty()) return@launch
                    val urls = tracks.map { source.url(it) }
                    player.play(tracks, urls, json.getInt("index").coerceIn(0, tracks.lastIndex), json.getLong("position"), autoplay = false)
                    played++
                } catch (e: Exception) {
                    // The folders moved or the server is away: start without the last session.
                }
            }
        }
    }

    // MARK: Artwork

    private fun followCover(entry: Entry?) {
        if (!showArtwork) return
        val skin = Look.skin.id
        if (cover != null && glowSkin != skin) {
            glowSkin = skin
            glow = cover?.let { ArtworkGlow.field(it, Tokens.display.toArgb(), Tokens.displayMuted.toArgb()) }
        }
        val album = entry?.albumPath
        if (album == coverFor) return
        coverFor = album
        coverJob?.cancel()
        if (entry == null) {
            cover = null
            glow = null
            artworkOrigin = null
            return
        }
        coverJob = viewModelScope.launch {
            val resolved = artwork.resolve(entry)
            val found = resolved.cover
            cover = found
            artworkOrigin = resolved.origin
            glowSkin = skin
            glow = found?.let { ArtworkGlow.field(it, Tokens.display.toArgb(), Tokens.displayMuted.toArgb()) }
            player.setArtwork(entry.path, found)
            // The server or the internet was away: look again in a minute, for the same album.
            if (resolved.origin == ArtworkOrigin.Offline) {
                delay(60_000)
                if (coverFor == album) coverFor = null
            }
        }
    }

    private fun open(server: String, session: JellyfinSource.Session) = JellyfinSource(server, session, account.deviceId, VERSION)

    private fun message(e: SourceException): String {
        val res = getApplication<Application>().resources
        return when (e.reason) {
            SourceException.Reason.ServerUnavailable -> res.getString(R.string.error_offline)
            SourceException.Reason.LoginFailed -> res.getString(R.string.error_login)
            SourceException.Reason.NoMusicLibrary -> res.getString(R.string.error_no_library)
            SourceException.Reason.UnexpectedResponse -> res.getString(R.string.error_unexpected)
            SourceException.Reason.MissingFolder -> res.getString(R.string.error_missing)
            SourceException.Reason.HttpStatus -> res.getString(R.string.error_status, e.status)
        }
    }

    override fun onCleared() {
        player.release()
    }

    companion object {
        const val VERSION = BuildConfig.VERSION_NAME
    }
}
