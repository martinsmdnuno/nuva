package pt.nunomartins.nuva

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import pt.nunomartins.nuva.library.Account
import pt.nunomartins.nuva.library.Entry
import pt.nunomartins.nuva.library.JellyfinSource
import pt.nunomartins.nuva.library.SourceException
import pt.nunomartins.nuva.player.PlayerModel

/** The app's state: the account, the folder being browsed, and the player. */
class AppModel(app: Application) : AndroidViewModel(app) {
    private val account = Account(app)
    val player = PlayerModel(app)
    private var source: JellyfinSource? = account.server?.let { server -> account.session?.let { open(server, it) } }

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
    /** Folders or the queue below the keys, as ⌘B swaps them on the Mac. */
    var showingFolders by mutableStateOf(true)
    var ambient by mutableStateOf(false)
    /** After moving between folders, the row the remote's focus goes to (null: the first). */
    var focusPath by mutableStateOf<String?>(null)
        private set
    /** Bumped when the list should take the focus, and when a folder starts playing (the play key takes it). */
    var focusList by mutableIntStateOf(0)
        private set
    var played by mutableIntStateOf(0)
        private set

    init {
        if (signedIn) load("")
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
    }

    fun open(folder: Entry) = load(folder.path, focus = null)

    /** Goes up a level, with the focus on the folder just left. */
    fun up() = load(path.substringBeforeLast('/', ""), focus = path)

    /** Plays the folder being browsed from `track` (or the top), and shows the queue. */
    fun playFolder(track: Entry? = null) {
        val source = source ?: return
        val tracks = entries.filter { !it.isFolder }
        if (tracks.isEmpty()) return
        viewModelScope.launch {
            try {
                val urls = tracks.map { source.url(it) }
                player.play(tracks, urls, track?.let { tracks.indexOf(it) }?.coerceAtLeast(0) ?: 0)
                showingFolders = false
                played++
            } catch (e: SourceException) {
                error = message(e)
            }
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
                focusPath = focus
                focusList++
            } catch (e: SourceException) {
                if (e.reason == SourceException.Reason.LoginFailed) signOut()
                error = message(e)
            } finally {
                loading = false
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
