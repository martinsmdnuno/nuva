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
import pt.nunomartins.nuva.audio.Audio
import pt.nunomartins.nuva.ui.AmbientScreen
import pt.nunomartins.nuva.ui.AmbientState
import pt.nunomartins.nuva.ui.Look
import pt.nunomartins.nuva.ui.Overlays
import pt.nunomartins.nuva.ui.PlayerScreen
import pt.nunomartins.nuva.ui.SignInScreen

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        Audio.init(this)
        Look.init(this)
        AmbientState.init(this)
        super.onCreate(savedInstanceState)
        setContent {
            val state by model.player.state.collectAsStateWithLifecycle()

            // The time and the bar are a readout: refresh them a few times a second, and remember
            // where the music is. A minute without the remote while it plays: the screen becomes the display.
            LaunchedEffect(Unit) {
                while (true) {
                    model.player.refresh()
                    val now = model.player.state.value
                    model.tick(now)
                    if (now.isPlaying && model.autoAmbient && model.signedIn && !model.ambient && model.overlay == null &&
                        System.currentTimeMillis() - lastInput > IDLE
                    ) model.ambient = true
                    delay(250)
                }
            }
            LaunchedEffect(model.ambient, state.isPlaying) {
                // Keeps the screen awake in ambient mode while music plays, like the Mac.
                if (model.ambient && state.isPlaying) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }

            // Back: closes what is open, then goes up a folder, then asks before leaving the app.
            BackHandler(enabled = model.signedIn) {
                when {
                    model.ambient -> model.ambient = false
                    model.overlay != null -> model.overlay = null
                    model.showingFolders && model.path.isNotEmpty() -> model.up()
                    else -> model.overlay = Overlay.ConfirmExit
                }
            }

            Box(Modifier.fillMaxSize()) {
                when {
                    !model.signedIn -> SignInScreen(model)
                    model.ambient -> AmbientScreen(model)
                    else -> {
                        PlayerScreen(model)
                        Overlays(model) { finish() }
                    }
                }
            }
        }
    }

    /** Seen before Compose: in ambient mode nothing on screen has the focus. */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        lastInput = System.currentTimeMillis()
        if (model.ambient && event.keyCode != KeyEvent.KEYCODE_BACK) {
            val resting = AmbientState.isResting(lastInput)
            AmbientState.noteInteraction()
            if (event.action != KeyEvent.ACTION_DOWN) return event.keyCode in AMBIENT_KEYS || super.dispatchKeyEvent(event)
            // Resting, the first key only wakes the screen.
            if (resting && event.keyCode in AMBIENT_KEYS) return true
            when (event.keyCode) {
                // ← → change the face, OK plays or pauses, ↑ ↓ leave (as Esc on the Mac; Back too).
                KeyEvent.KEYCODE_DPAD_LEFT -> AmbientState.changeFace(-1)
                KeyEvent.KEYCODE_DPAD_RIGHT -> AmbientState.changeFace(1)
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> model.player.playPause()
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> model.ambient = false
                else -> return super.dispatchKeyEvent(event)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private var lastInput = System.currentTimeMillis()

    private companion object {
        const val IDLE = 60_000L
        val AMBIENT_KEYS = setOf(
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
        )
    }
}
