package pt.nunomartins.nuva

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers.Main
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Asks GitHub for the latest release, at most once a day, as the Mac app does. The Android TV app is
 * the release asset named "NuVa-AndroidTV-<version>.apk". Unlike the Mac, the TV can then update
 * itself, but only when asked (Menu ▸ Update to X): the APK goes from the release straight into
 * Android's installer, which asks to confirm and installs it over this one (same key, so settings,
 * sign-in and the queue stay). Nothing is downloaded or installed without that.
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

    /** How much of the update has come down (0–1) while it downloads, null otherwise. */
    var downloading by mutableStateOf<Float?>(null)
        private set
    /** Why the last update didn't start, for the menu: null when nothing went wrong. */
    var problem by mutableStateOf<Problem?>(null)
        private set

    enum class Problem { NeedsPermission, Failed }

    /**
     * Downloads the available version and hands it to Android's installer, which asks to confirm.
     * The first time, Android must let NuVa install apps: its settings open on that switch instead.
     */
    fun install(context: Context, scope: CoroutineScope) {
        val target = available ?: return
        if (downloading != null) return
        if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
            problem = Problem.NeedsPermission
            runCatching {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            return
        }
        problem = null
        downloading = 0f
        scope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { download(context, target) { done -> scope.launch(Main) { downloading = done } } }.isSuccess
            }
            downloading = null
            if (!ok) problem = Problem.Failed
        }
    }

    /** The release's APK, streamed into an installer session that is then committed (Android asks to confirm). */
    private fun download(context: Context, target: String, progress: (Float) -> Unit) {
        val c = URL("https://github.com/martinsmdnuno/nuva/releases/download/v$target/NuVa-AndroidTV-$target.apk").openConnection() as HttpURLConnection
        c.connectTimeout = 15_000
        c.readTimeout = 30_000
        c.setRequestProperty("User-Agent", "NuVa-AndroidTV/$version")
        try {
            if (c.responseCode != 200) error("HTTP ${c.responseCode}")
            val length = c.contentLengthLong
            val installer = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(context.packageName)
            val id = installer.createSession(params)
            installer.openSession(id).use { session ->
                session.openWrite("NuVa-AndroidTV.apk", 0, if (length > 0) length else -1).use { out ->
                    c.inputStream.use { input ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        var shown = -1
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                            total += n
                            val percent = if (length > 0) (total * 100 / length).toInt() else 0
                            if (percent != shown) { shown = percent; progress(percent / 100f) }
                        }
                    }
                    session.fsync(out)
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                val answer = PendingIntent.getBroadcast(context, id, Intent(context, InstallAnswer::class.java), flags)
                session.commit(answer.intentSender)
            }
        } finally {
            c.disconnect()
        }
    }

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

/** The installer's answer: it needs the person to confirm (its screen opens), or it is done. */
class InstallAnswer : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE) != PackageInstaller.STATUS_PENDING_USER_ACTION) return
        val confirm = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT)
        confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)?.let { runCatching { context.startActivity(it) } }
    }
}
