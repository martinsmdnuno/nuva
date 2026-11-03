package pt.nunomartins.nuva

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Asks GitHub for the latest release, at most once a day, as the Mac app does: a notice only,
 * never a download. The Android TV app is the release asset named "NuVa-AndroidTV-<version>.apk".
 */
class Updates(context: Context, private val version: String) {
    private val prefs = context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    /** A newer version's number, when there is one. */
    var available by mutableStateOf(prefs.getString("available", null)?.takeIf { newer(it, version) })
        private set
    var checking by mutableStateOf(false)
        private set
    /** The last check's answer, for the settings: true up to date, false failed, null not asked. */
    var upToDate by mutableStateOf<Boolean?>(null)
        private set

    fun checkDaily(scope: CoroutineScope) {
        if (System.currentTimeMillis() - prefs.getLong("checkedAt", 0) > 24 * 3600 * 1000L) check(scope)
    }

    fun check(scope: CoroutineScope) {
        if (checking) return
        checking = true
        scope.launch {
            val latest = withContext(Dispatchers.IO) { latest() }
            checking = false
            prefs.edit().putLong("checkedAt", System.currentTimeMillis()).apply()
            if (latest == null) {
                upToDate = false
                return@launch
            }
            available = latest.takeIf { newer(it, version) }
            prefs.edit().putString("available", available).apply()
            upToDate = available == null
        }
    }

    /** The newest Android TV version in the latest release, "" when it has none, null when GitHub can't be reached. */
    private fun latest(): String? = try {
        val c = URL("https://api.github.com/repos/martinsmdnuno/nuva/releases/latest").openConnection() as HttpURLConnection
        c.connectTimeout = 15_000
        c.readTimeout = 15_000
        c.setRequestProperty("Accept", "application/vnd.github+json")
        c.setRequestProperty("User-Agent", "NuVa-AndroidTV/$version")
        val body = c.inputStream.use { it.readBytes().decodeToString() }
        c.disconnect()
        val assets = JSONObject(body).getJSONArray("assets")
        (0 until assets.length())
            .mapNotNull { Regex("""^NuVa-AndroidTV-([\d.]+)\.apk$""").find(assets.getJSONObject(it).getString("name"))?.groupValues?.get(1) }
            .maxWithOrNull { a, b -> if (newer(a, b)) 1 else if (newer(b, a)) -1 else 0 } ?: ""
    } catch (e: Exception) {
        null
    }

    companion object {
        /** "1.11" is newer than "1.10.1". */
        fun newer(a: String, b: String): Boolean {
            if (a.isEmpty()) return false
            val x = a.split('.').map { it.toIntOrNull() ?: 0 }
            val y = b.split('.').map { it.toIntOrNull() ?: 0 }
            for (i in 0 until maxOf(x.size, y.size)) {
                val p = x.getOrElse(i) { 0 }
                val q = y.getOrElse(i) { 0 }
                if (p != q) return p > q
            }
            return false
        }
    }
}
