package com.aurora.aurora_music

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.system.Os
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException

class MainActivity : AudioServiceActivity() {
    private val sourceWorkers = ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(8))
    private val controls = Executors.newSingleThreadExecutor()
    private val pcmReads = Executors.newFixedThreadPool(2)
    private val stderrReaders = Executors.newFixedThreadPool(2)
    private val timeouts = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, String>()
    private val cancelledDownloads = ConcurrentHashMap.newKeySet<String>()
    private val pcm = ConcurrentHashMap<String, Process>()
    private val pcmErrors = ConcurrentHashMap<String, StringBuilder>()
    private var initialized = false

    @Synchronized private fun initialize() {
        if (initialized) return
        try {
            installBundledYtDlp()
            YoutubeDL.init(applicationContext)
            FFmpeg.init(applicationContext)
        } catch (error: Exception) {
            val details = generateSequence(error) { it.cause as? Exception }
                .mapNotNull { it.message }.take(4).joinToString(": ")
            throw IOException(redact(details), error)
        }
        initialized = true
    }

    private fun installBundledYtDlp() {
        val payload = resources.openRawResource(R.raw.ytdlp).use { it.readBytes() }
        val expectedHash = "1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6"
        if (sha256(payload) != expectedHash) throw IOException("Bundled yt-dlp integrity check failed")

        val directory = File(noBackupFilesDir, "youtubedl-android/yt-dlp")
        val target = File(directory, "yt-dlp")
        if (target.isFile && target.inputStream().use { sha256(it.readBytes()) } == expectedHash) return
        if (!directory.exists() && !directory.mkdirs()) throw IOException("Unable to prepare yt-dlp directory")

        val temporary = File.createTempFile(".yt-dlp-", ".tmp", directory)
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(payload)
                stream.fd.sync()
            }
            Os.rename(temporary.absolutePath, target.absolutePath)
        } catch (error: Exception) {
            temporary.delete()
            throw IOException("Unable to install bundled yt-dlp", error)
        }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val source = MethodChannel(engine.dartExecutor.binaryMessenger, "aurora/source")
        source.setMethodCallHandler { call, result ->
            if (call.method == "cancel") {
                val cancelledJob = call.argument<String>("jobId")
                if (cancelledJob == null) { result.error("SOURCE_ERROR", "Identificador requerido", null); return@setMethodCallHandler }
                cancelledDownloads.add(cancelledJob)
                controls.execute {
                    try {
                        jobs[cancelledJob]?.let { YoutubeDL.destroyProcessById(it) }
                        main.post { result.success(null) }
                    } catch(error: Exception) { main.post { result.error("SOURCE_ERROR", redact(error.message), null) } }
                }
                return@setMethodCallHandler
            }
            val work = Runnable {
                try {
                    initialize()
                    val target = call.argument<String>("target") ?: ""
                    val answer: Any? = when (call.method) {
                        "search", "playlist", "resolve" -> {
                            if (call.method == "search") {
                                require(target.matches(Regex("ytsearch[0-9]{1,2}:.{1,500}"))) { "Búsqueda inválida" }
                            } else validateYouTube(target)
                            val request = request(target, call.argument<String>("cookieFile"))
                            request.addOption("--dump-single-json")
                            if (call.method == "resolve") {
                                request.addOption("--no-playlist")
                                request.addOption("-f", "bestaudio/best")
                            } else {
                                request.addOption("--flat-playlist")
                                request.addOption("--playlist-end", (call.argument<Int>("limit") ?: 20).coerceIn(1, 200))
                            }
                            val internalId = UUID.randomUUID().toString()
                            val watchdog = timeouts.schedule(Runnable { YoutubeDL.destroyProcessById(internalId) }, 90, TimeUnit.SECONDS)
                            try { YoutubeDL.execute(request, internalId).out }
                            finally { watchdog.cancel(false) }
                        }
                        "download" -> {
                            validateYouTube(target)
                            val directory = File(requireNotNull(call.argument<String>("directory"))).canonicalFile
                            // Downloads remain inside app storage; export is performed separately via SAF.
                            require(directory.toPath().startsWith(filesDir.canonicalFile.toPath()) || directory.toPath().startsWith(cacheDir.canonicalFile.toPath()) || directory.toPath().startsWith(getExternalFilesDir(null)?.canonicalFile?.toPath() ?: filesDir.toPath())) { "Destino fuera del almacenamiento de la app" }
                            val job = requireNotNull(call.argument<String>("jobId"))
                            check(!cancelledDownloads.remove(job)) { "Descarga cancelada" }
                            val internalId = UUID.randomUUID().toString()
                            require(jobs.putIfAbsent(job, internalId) == null) { "Descarga duplicada" }
                            val request = request(target, call.argument<String>("cookieFile"))
                            request.addOption("--no-playlist")
                            request.addOption("-f", "bestaudio/best")
                            request.addOption("-x")
                            request.addOption("--audio-format", "mp3")
                            request.addOption("--audio-quality", "0")
                            request.addOption("-o", File(directory, "audio.%(ext)s").absolutePath)
                            try {
                                YoutubeDL.execute(request, internalId) { progress, _, _ ->
                                    if (cancelledDownloads.contains(job)) YoutubeDL.destroyProcessById(internalId)
                                    main.post { source.invokeMethod("progress", mapOf("jobId" to job, "progress" to (progress / 100.0).coerceIn(0.0, 1.0))) }
                                }
                                check(!cancelledDownloads.contains(job)) { "Descarga cancelada" }
                            } finally { jobs.remove(job); cancelledDownloads.remove(job) }
                            null
                        }
                        "diagnose" -> YoutubeDL.execute(request("").apply { addOption("--version") }).out.trim() + " · Python / QuickJS / FFmpeg integrados"
                        else -> throw IllegalArgumentException("Método no disponible")
                    }
                    main.post { result.success(answer) }
                } catch (error: Exception) { main.post { result.error("SOURCE_ERROR", redact(error.message), null) } }
                catch (error: LinkageError) { main.post { result.error("SOURCE_ERROR", redact(error.message), null) } }
            }
            try { sourceWorkers.execute(work) }
            catch (_: RejectedExecutionException) { result.error("SOURCE_BUSY", "La fuente está ocupada. Inténtalo nuevamente.", null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "aurora/pcm").setMethodCallHandler { call, result ->
            val lane = if (call.method == "read") pcmReads else controls
            lane.execute {
                try {
                    initialize()
                    val answer: Any? = when(call.method) {
                        "start" -> {
                            val input = requireNotNull(call.argument<String>("input"))
                            val uri = Uri.parse(input)
                            require(uri.scheme == "https" || File(input).isFile) { "Fuente de audio inválida" }
                            val args = mutableListOf(File(applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath, "-nostdin", "-v", "error")
                            val headers = call.argument<Map<String,String>>("headers") ?: emptyMap()
                            if (uri.scheme == "https") {
                                args.addAll(listOf("-rw_timeout", "15000000", "-tls_verify", "1", "-ca_file", File(noBackupFilesDir,"youtubedl-android/packages/python/usr/etc/tls/cert.pem").absolutePath))
                                if(headers.isNotEmpty()) {
                                    require(headers.all { (k,v) -> k.matches(Regex("[A-Za-z0-9-]+")) && !v.contains('\r') && !v.contains('\n') })
                                    args.addAll(listOf("-headers", headers.entries.joinToString("") { "${it.key}: ${it.value}\r\n" }))
                                }
                            }
                            val offset = (call.argument<Number>("offsetMs")?.toLong() ?: 0).coerceAtLeast(0)
                            args.addAll(listOf("-ss", (offset/1000.0).toString(), "-i", input, "-vn", "-f", "f32le", "-acodec", "pcm_f32le", "-ar", "48000", "-ac", "2", "pipe:1"))
                            val builder = ProcessBuilder(args)
                            val packages = File(noBackupFilesDir,"youtubedl-android/packages")
                            builder.environment()["LD_LIBRARY_PATH"] = "${packages.absolutePath}/ffmpeg/usr/lib:${packages.absolutePath}/python/usr/lib"
                            val process = builder.start()
                            val id = UUID.randomUUID().toString()
                            pcm[id] = process
                            val errors = StringBuilder()
                            pcmErrors[id] = errors
                            stderrReaders.execute {
                                try {
                                    process.errorStream.bufferedReader().useLines { lines ->
                                        lines.forEach { synchronized(errors) { if(errors.length<4096) errors.append(it).append('\n') } }
                                    }
                                } catch (_: IOException) {
                                    // stop/seek closes the stream while this worker is reading.
                                }
                            }
                            mapOf("sessionId" to id)
                        }
                        "read" -> {
                            val id = requireNotNull(call.argument<String>("sessionId"))
                            val process = requireNotNull(pcm[id]) { "Sesión terminada" }
                            val size = (call.argument<Int>("maxBytes") ?: 65536).coerceIn(8,65536)
                            val bytes = ByteArray(size)
                            val count = process.inputStream.read(bytes)
                            if(count < 0) {
                                val code = process.waitFor()
                                pcm.remove(id)
                                val errors = pcmErrors.remove(id)
                                if(code != 0) throw IllegalStateException("FFmpeg: ${errors?.toString()}")
                                ByteArray(0)
                            } else bytes.copyOf(count)
                        }
                        "stop" -> {
                            val id = call.argument<String>("sessionId")
                            pcm.remove(id)?.let { it.destroy(); it.inputStream.close(); it.errorStream.close() }
                            pcmErrors.remove(id)
                            null
                        }
                        else -> throw IllegalArgumentException("Método PCM no disponible")
                    }
                    main.post { result.success(answer) }
                } catch(error: Exception) { main.post { result.error("PCM_ERROR",redact(error.message),null) } }
                catch(error: LinkageError) { main.post { result.error("PCM_ERROR",redact(error.message),null) } }
            }
        }
    }
    private fun request(target: String, cookiePath: String? = null) = YoutubeDLRequest(target).apply {
        addOption("--ignore-config"); addOption("--no-plugin-dirs"); addOption("--no-remote-components"); addOption("--no-warnings")
        addOption("--socket-timeout", "15"); addOption("--retries", "2")
        if (cookiePath != null) {
            val cookies = File(cookiePath).canonicalFile
            require(cookies.toPath().startsWith(filesDir.canonicalFile.toPath()) && cookies.isFile && cookies.length() in 1..1048576) { "Archivo de sesión inválido" }
            val header = cookies.bufferedReader().use { it.readLine() }
            require(header in setOf("# Netscape HTTP Cookie File", "# HTTP Cookie File")) { "Usa cookies en formato Netscape" }
            val hasYoutube = cookies.useLines { lines -> lines.drop(1).any { line ->
                val domain = line.removePrefix("#HttpOnly_").substringBefore('\t')
                domain in setOf("youtube.com", ".youtube.com") && line.split('\t').size == 7
            } }
            require(hasYoutube) { "El archivo debe incluir cookies de YouTube" }
            addOption("--cookies", cookies.absolutePath)
        }
    }
    private fun validateYouTube(value: String) {
        val uri = Uri.parse(value)
        require(uri.scheme == "https" && uri.host in setOf("youtube.com","www.youtube.com","music.youtube.com","m.youtube.com","youtu.be") && uri.userInfo == null && (uri.port == -1 || uri.port == 443)) { "Usa un enlace HTTPS de YouTube" }
    }
    private fun redact(message: String?): String = (message ?: "Error de audio").replace(Regex("https?://[^\\s<>\\\"']+")) { match ->
        try { Uri.parse(match.value).buildUpon().clearQuery().fragment(null).build().toString() }
        catch (_: Exception) { "[URL]" }
    }
}
