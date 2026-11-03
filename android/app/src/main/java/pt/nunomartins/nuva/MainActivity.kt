package pt.nunomartins.nuva

import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import pt.nunomartins.nuva.ui.AmbientScreen
import pt.nunomartins.nuva.ui.PlayerScreen
import pt.nunomartins.nuva.ui.SignInScreen

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val state by model.player.state.collectAsStateWithLifecycle()

            // The time and the bar are a readout: refresh them a few times a second.
            // A minute without the remote while music plays: the screen becomes the display.
            LaunchedEffect(Unit) {
                while (true) {
                    model.player.refresh()
                    val playing = model.player.state.value.isPlaying
                    if (playing && model.signedIn && !model.ambient && System.currentTimeMillis() - lastInput > IDLE) model.ambient = true
                    delay(250)
                }
            }
            LaunchedEffect(model.ambient, state.isPlaying) {
                // Keeps the screen awake in ambient mode while music plays, like the Mac.
                if (model.ambient && state.isPlaying) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }

            BackHandler(enabled = model.ambient) { model.ambient = false }
            BackHandler(enabled = !model.ambient && model.signedIn && model.showingFolders && model.path.isNotEmpty()) { model.up() }

            Box(Modifier.fillMaxSize()) {
                when {
                    !model.signedIn -> SignInScreen(model)
                    model.ambient -> AmbientScreen(model)
                    else -> PlayerScreen(model)
                }
            }
        }
    }

    /** Seen before Compose: in ambient mode nothing on screen has the focus. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        lastInput = System.currentTimeMillis()
        // In ambient mode the arrows and OK only wake the screen; media keys still go to the player.
        if (model.ambient && event.keyCode in WAKE_KEYS) {
            if (event.action == KeyEvent.ACTION_UP) model.ambient = false
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private var lastInput = System.currentTimeMillis()

    private companion object {
        const val IDLE = 60_000L
        val WAKE_KEYS = setOf(
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        )
    }
}
