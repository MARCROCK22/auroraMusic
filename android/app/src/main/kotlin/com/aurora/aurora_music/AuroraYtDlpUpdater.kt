package com.aurora.aurora_music

import android.content.Context
import android.system.Os
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.locks.ReentrantReadWriteLock
import java.util.zip.ZipInputStream

/** Only the interpreted Python payload is replaceable; native runtimes stay in the APK. */
class AuroraYtDlpUpdater(private val context: Context, private val sourceLock: ReentrantReadWriteLock) {
    companion object {
        const val BUNDLED_VERSION = "2026.10.10.233141"
        const val BUNDLED_HASH = "f40b6a9e4c5786360953911cab5d2f87507626b8fb7bfee3f8f1c2e5cf341fae"
        private const val RELEASES = "https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest"
    }
    private val preferences = context.getSharedPreferences("aurora-ytdlp-nightly", Context.MODE_PRIVATE)
    private val directory = File(context.noBackupFilesDir, "youtubedl-android/yt-dlp")
    private val target = File(directory, "yt-dlp")
    private val backup = File(directory, "yt-dlp.previous")
    @Volatile private var checking = false
    @Volatile var requiresRecovery = false
        private set

    @Synchronized fun installBundle() {
        val bundled = context.resources.openRawResource(R.raw.ytdlp).use { it.readBytes() }
        check(NightlyIntegrity.sha256(bundled) == BUNDLED_HASH) { "Bundled yt-dlp integrity check failed" }
        directory.mkdirs()
        val installed = preferences.getString("installedHash", null)
        val installedVersion = preferences.getString("installedVersion", "") ?: ""
        if (!requiresRecovery && !preferences.contains("pendingHash") && target.isFile && NightlyIntegrity.sha256(target.readBytes()) == installed && installedVersion >= BUNDLED_VERSION) return
        // A process death between rename and journal commit restores the verified previous file.
        val previous = preferences.getString("previousHash", null)
        if (backup.isFile && previous != null && NightlyIntegrity.sha256(backup.readBytes()) == previous) {
            atomicWrite(target, backup.readBytes())
            check(preferences.edit().putString("installedHash", previous)
                .putString("installedVersion", preferences.getString("previousVersion", ""))
                .remove("sourceCommit").remove("pendingHash").commit())
            requiresRecovery = false
            if ((preferences.getString("installedVersion", "") ?: "") >= BUNDLED_VERSION) return
        }
        atomicWrite(target, bundled)
        check(preferences.edit().putString("installedHash", BUNDLED_HASH)
            .putString("installedVersion", BUNDLED_VERSION).remove("pendingHash").commit())
        requiresRecovery = false
    }

    @Synchronized fun checkForUpdate(canInstall: () -> Boolean, probeVersion: () -> String): String {
        if (checking || !canInstall()) return result("deferred")
        val now = System.currentTimeMillis()
        if (now - preferences.getLong("lastCheckAt", 0) < 24 * 60 * 60 * 1000L) return result("throttled")
        checking = true
        var replaced = false
        var installLocked = false
        try {
            check(preferences.edit().putLong("lastCheckAt", now).commit())
            val release = JSONObject(fetch(RELEASES, 1024 * 1024).toString(Charsets.UTF_8))
            val version = release.getString("tag_name")
            require(version.matches(Regex("\\d{4}\\.\\d{2}\\.\\d{2}\\.\\d{6}")) && !release.getBoolean("draft"))
            val base = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/$version/"
            val assets = release.getJSONArray("assets")
            for (name in listOf("yt-dlp", "SHA2-256SUMS")) {
                val matches = (0 until assets.length()).map { assets.getJSONObject(it) }.filter { it.optString("name") == name }
                require(matches.size == 1 && matches.single().getString("browser_download_url") == base + name)
            }
            val expected = NightlyIntegrity.checksum(fetch(base + "SHA2-256SUMS", 1024 * 1024).toString(Charsets.UTF_8))
            if (target.isFile && NightlyIntegrity.sha256(target.readBytes()) == expected) return result("upToDate", version)
            val payload = fetch(base + "yt-dlp", 32 * 1024 * 1024)
            NightlyIntegrity.verifyPayload(payload, expected)
            val commit = Regex("Generated from: https://github\\.com/yt-dlp/yt-dlp/commit/([0-9a-f]{40})(?:\\s|$)")
                .find(release.optString("body"))?.groupValues?.get(1) ?: throw IOException("Missing nightly provenance")
            val licenses = File(directory, "licenses").apply { mkdirs() }
            for (notice in listOf("LICENSE", "THIRD_PARTY_LICENSES.txt")) {
                val bytes = fetch("https://raw.githubusercontent.com/yt-dlp/yt-dlp/$commit/$notice", 1024 * 1024)
                require(bytes.isNotEmpty())
                atomicWrite(File(licenses, "$version-$notice"), bytes)
            }
            if (!sourceLock.writeLock().tryLock()) return result("deferred")
            installLocked = true
            if (!canInstall()) return result("deferred")
            val previous = target.readBytes()
            val previousHash = NightlyIntegrity.sha256(previous)
            require(previousHash == preferences.getString("installedHash", null))
            atomicWrite(backup, previous)
            requiresRecovery = true
            check(preferences.edit().putString("previousHash", previousHash)
                .putString("previousVersion", preferences.getString("installedVersion", ""))
                .putString("pendingHash", expected).commit())
            atomicWrite(target, payload)
            replaced = true
            require(probeVersion().trim() == version) { "Updated yt-dlp failed its version check" }
            check(preferences.edit().putString("installedHash", expected).putString("installedVersion", version)
                .putString("sourceCommit", commit).remove("pendingHash").commit())
            requiresRecovery = false
            return result("updated", version)
        } catch (_: Exception) {
            if (replaced) {
                try {
                    val bytes = backup.readBytes()
                    require(NightlyIntegrity.sha256(bytes) == preferences.getString("previousHash", null))
                    atomicWrite(target, bytes)
                    check(preferences.edit()
                        .putString("installedHash", preferences.getString("previousHash", null))
                        .putString("installedVersion", preferences.getString("previousVersion", BUNDLED_VERSION))
                        .remove("sourceCommit").remove("pendingHash").commit())
                    requiresRecovery = false
                } catch (_: Exception) { return result("failed", error = "La actualización falló. Se conservó la copia anterior para recuperarla al iniciar.") }
            }
            return result("failed", error = "No se pudo actualizar yt-dlp. Se conserva la versión anterior.")
        } finally {
            if (installLocked) sourceLock.writeLock().unlock()
            checking = false
        }
    }

    private fun result(status: String, version: String? = null, error: String? = null): String =
        JSONObject().put("status", status).put("version", version ?: preferences.getString("installedVersion", BUNDLED_VERSION))
            .put("error", error ?: JSONObject.NULL).toString()

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val staged = File.createTempFile(".aurora-ytdlp-", ".tmp", directory)
        try {
            FileOutputStream(staged).use { it.write(bytes); it.fd.sync() }
            Os.rename(staged.absolutePath, file.absolutePath)
        } finally { staged.delete() }
    }

    private fun fetch(address: String, limit: Int): ByteArray {
        var next = URL(address)
        repeat(6) {
            require(next.protocol == "https" && next.userInfo == null && (next.port == -1 || next.port == 443) && next.host in setOf(
                "api.github.com", "github.com", "raw.githubusercontent.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"))
            val connection = next.openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                connection.setRequestProperty("User-Agent", "Aurora-nightly-updater")
                val status = connection.responseCode
                if (status in listOf(301, 302, 303, 307, 308)) {
                    next = URL(next, connection.getHeaderField("Location") ?: throw IOException("Missing redirect"))
                } else {
                    require(status == 200)
                    require(connection.contentLengthLong <= limit)
                    val deadline = System.currentTimeMillis() + 90000
                    return connection.inputStream.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(65536)
                        while (true) {
                            require(System.currentTimeMillis() <= deadline)
                            val count = input.read(chunk)
                            if (count < 0) break
                            require(output.size() + count <= limit)
                            output.write(chunk, 0, count)
                        }
                        output.toByteArray()
                    }
                }
            } finally { connection.disconnect() }
        }
        throw IOException("Too many update redirects")
    }
}

internal object NightlyIntegrity {
    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    fun checksum(text: String): String {
        val matches = text.lineSequence().mapNotNull { Regex("^([a-fA-F0-9]{64})\\s+\\*?yt-dlp\\s*$").matchEntire(it)?.groupValues?.get(1) }.toList()
        require(matches.size == 1) { "Missing or ambiguous official checksum" }
        return matches.single().lowercase()
    }
    fun verifyPayload(bytes: ByteArray, expected: String) {
        require(bytes.size >= 4 && bytes.size <= 32 * 1024 * 1024 && sha256(bytes) == expected)
        require(bytes.take(4).toByteArray().toString(Charsets.US_ASCII) == "#!/u")
        val offset = (4 until minOf(bytes.size - 3, 256)).firstOrNull { bytes[it] == 0x50.toByte() && bytes[it + 1] == 0x4b.toByte() && bytes[it + 2] == 3.toByte() && bytes[it + 3] == 4.toByte() } ?: throw IOException("Missing zipimport payload")
        val required = mutableSetOf("__main__.py", "yt_dlp/version.py", "yt_dlp_ejs/__init__.py")
        ZipInputStream(ByteArrayInputStream(bytes, offset, bytes.size - offset)).use { zip ->
            var entries = 0
            while (required.isNotEmpty()) {
                val entry = zip.nextEntry ?: break
                require(++entries <= 2000)
                required.remove(entry.name)
                zip.closeEntry()
            }
        }
        require(required.isEmpty()) { "Incomplete yt-dlp Python/EJS bundle" }
    }
}
