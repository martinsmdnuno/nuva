package pt.nunomartins.nuva.library

import android.content.Context
import java.util.UUID

/** The Jellyfin server the app signed in to. Keeps the access token, never the password. */
class Account(context: Context) {
    private val prefs = context.getSharedPreferences("account", Context.MODE_PRIVATE)

    val deviceId: String =
        prefs.getString("deviceId", null) ?: UUID.randomUUID().toString().also { prefs.edit().putString("deviceId", it).apply() }

    val server: String? get() = prefs.getString("server", null)
    val username: String? get() = prefs.getString("username", null)

    val session: JellyfinSource.Session?
        get() {
            val token = prefs.getString("token", null) ?: return null
            val userId = prefs.getString("userId", null) ?: return null
            return JellyfinSource.Session(token, userId)
        }

    fun save(server: String, username: String, session: JellyfinSource.Session) {
        prefs.edit()
            .putString("server", server)
            .putString("username", username)
            .putString("token", session.token)
            .putString("userId", session.userId)
            .apply()
    }

    /** Forgets the token; the server and the user stay, to sign in again quickly. */
    fun signOut() {
        prefs.edit().remove("token").remove("userId").apply()
    }
}
