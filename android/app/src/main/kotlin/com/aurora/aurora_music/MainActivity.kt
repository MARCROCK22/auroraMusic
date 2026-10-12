package com.aurora.aurora_music

import android.net.Uri
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.system.Os
import android.system.OsConstants
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
import java.util.concurrent.TimeoutException
import java.util.concurrent.FutureTask

class MainActivity : AudioServiceActivity() {
    private val sourceWorkers = ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(8))
    private val controls = Executors.newSingleThreadExecutor()
    private val pcmReads = Executors.newFixedThreadPool(2)
    private val stderrReaders = Executors.newFixedThreadPool(2)
    private val timeouts = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<String, String>()
    private val validationProcesses = ConcurrentHashMap<String, Process>()
    private val cancelledDownloads = ConcurrentHashMap.newKeySet<String>()
    private val timedOutDownloads = ConcurrentHashMap.newKeySet<String>()
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
                val alias = cancelledJob.removePrefix("resolve:")
                if (alias != cancelledJob) {
                    cancelledDownloads.add(cancelledJob)
                    jobs.keys.filter { it.startsWith("resolve-$alias-") }.forEach { cancelledDownloads.add(it) }
                } else cancelledDownloads.add(cancelledJob)
                controls.execute {
                    try {
                        val matching = if (alias != cancelledJob) jobs.filterKeys { it.startsWith("resolve-$alias-") } else mapOf(cancelledJob to jobs[cancelledJob])
                        matching.values.filterNotNull().forEach { YoutubeDL.destroyProcessById(it) }
                        validationProcesses[cancelledJob]?.destroy()
                        main.post { result.success(null) }
                    } catch(error: Exception) { main.post { result.error("SOURCE_ERROR", redact(error.message), null) } }
                }
                return@setMethodCallHandler
            }
            val work = Runnable {
                try {
                    val job = call.argument<String>("jobId")
                    if (call.method == "cacheAudio" || call.method == "progressiveAudio") {
                        requireNotNull(job) { "Identificador requerido" }
                        val videoId = requireNotNull(call.argument<String>("videoId"))
                        check(!cancelledDownloads.remove(job) && !cancelledDownloads.remove("resolve:$videoId")) { "Descarga cancelada" }
                    }
                    initialize()
                    val target = call.argument<String>("target") ?: ""
                    val answer: Any? = when (call.method) {
                        "search", "playlist", "resolve", "progressiveInfo" -> {
                            if (call.method == "search") {
                                require(target.matches(Regex("ytsearch[0-9]{1,2}:.{1,500}"))) { "Búsqueda inválida" }
                            } else validateYouTube(target)
                            val request = request(target, call.argument<String>("cookieFile"))
                            request.addOption("--dump-single-json")
                            if (call.method == "resolve" || call.method == "progressiveInfo") {
                                request.addOption("--no-playlist")
                                request.addOption("-f", if (call.method == "progressiveInfo") "bestaudio[ext=webm][protocol=https]/bestaudio/best" else "bestaudio/best")
                            } else {
                                request.addOption("--flat-playlist")
                                request.addOption("--playlist-end", (call.argument<Int>("limit") ?: 20).coerceIn(1, 200))
                            }
                            val internalId = UUID.randomUUID().toString()
                            val progressiveJob = if (call.method == "progressiveInfo") requireNotNull(job) else null
                            if (progressiveJob != null) {
                                check(!cancelledDownloads.contains(progressiveJob)) { "Descarga cancelada" }
                                require(jobs.putIfAbsent(progressiveJob, internalId) == null) { "Descarga duplicada" }
                            }
                            val watchdog = timeouts.schedule(Runnable { YoutubeDL.destroyProcessById(internalId) }, 90, TimeUnit.SECONDS)
                            try {
                                val output = YoutubeDL.execute(request, internalId).out
                                check(progressiveJob == null || !cancelledDownloads.contains(progressiveJob)) { "Descarga cancelada" }
                                output
                            } finally {
                                watchdog.cancel(false)
                                if (progressiveJob != null) jobs.remove(progressiveJob)
                            }
                        }
                        "cacheAudio", "progressiveAudio" -> {
                            validateYouTube(target)
                            val videoId = requireNotNull(call.argument<String>("videoId"))
                            require(videoId.matches(Regex("[A-Za-z0-9_-]{11}"))) { "Identificador de video inv\u00e1lido" }
                            val uri = Uri.parse(target)
                            val targetId = if (uri.host == "youtu.be") uri.lastPathSegment else uri.getQueryParameter("v")
                            require(targetId == videoId) { "El identificador de video no coincide con el enlace" }
                            val support = filesDir.canonicalFile
                            val directory = File(requireNotNull(call.argument<String>("directory"))).canonicalFile
                            require(isWithin(directory, support) && directory.isDirectory) { "Destino de cach\u00e9 fuera del almacenamiento privado" }
                            val jobId = requireNotNull(job)
                            check(!cancelledDownloads.contains(jobId)) { "Descarga cancelada" }
                            val internalId = UUID.randomUUID().toString()
                            require(jobs.putIfAbsent(jobId, internalId) == null) { "Descarga duplicada" }
                            val watchdog = timeouts.schedule(Runnable {
                                timedOutDownloads.add(jobId)
                                try { YoutubeDL.destroyProcessById(internalId) } catch (_: Exception) { }
                            }, 30, TimeUnit.MINUTES)
                            try {
                                val request = request(target, call.argument<String>("cookieFile"))
                                request.addOption("--no-playlist")
                                val progressive = call.method == "progressiveAudio"
                                if (progressive) {
                                    val format = requireNotNull(call.argument<String>("formatId"))
                                    require(format.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "Formato de audio invalido" }
                                    request.addOption("-f", "$format[ext=webm][protocol=https]")
                                    request.addOption("--no-part")
                                    request.addOption("--no-continue")
                                    request.addOption("--fixup", "never")
                                } else request.addOption("-f", "bestaudio/best")
                                request.addOption("--max-filesize", "512M")
                                request.addOption("-o", File(directory, if (progressive) "audio.webm" else "audio.%(ext)s").absolutePath)
                                YoutubeDL.execute(request, internalId) { progress, _, _ ->
                                    if (cancelledDownloads.contains(jobId)) YoutubeDL.destroyProcessById(internalId)
                                    main.post { source.invokeMethod("progress", mapOf("jobId" to jobId, "progress" to (progress / 100.0).coerceIn(0.0, 1.0))) }
                                }
                                check(!timedOutDownloads.contains(jobId)) { "La descarga de audio superó 30 minutos" }
                                check(!cancelledDownloads.contains(jobId)) { "Descarga cancelada" }
                                val outputs = directory.listFiles()?.filter {
                                    it.name.matches(Regex("audio\\.[A-Za-z0-9]{1,8}")) &&
                                        isRegularFileNoFollow(it) && it.canonicalFile.parentFile == directory
                                }.orEmpty()
                                require(outputs.size == 1 && outputs.single().length() in 1..(512L * 1024 * 1024)) { "Descarga de audio incompleta o inv\u00e1lida" }
                                val duration = audioDuration(outputs.single())
                                check(!timedOutDownloads.contains(jobId)) { "La descarga de audio superó 30 minutos" }
                                check(!cancelledDownloads.contains(jobId)) { "Descarga cancelada" }
                                duration.toString()
                            } finally {
                                watchdog.cancel(false)
                                jobs.remove(jobId)
                                cancelledDownloads.remove(jobId)
                                timedOutDownloads.remove(jobId)
                            }
                        }
                        "probeAudio" -> {
                            val support = filesDir.canonicalFile
                            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                            require(isWithin(file, support) && isRegularFileNoFollow(file) && file.length() in 1..(512L * 1024 * 1024)) { "Archivo de audio fuera de la cach\u00e9 privada" }
                            audioDuration(file).toString()
                        }
                        "validateProgressiveAudio" -> {
                            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                            require(isWithin(file, filesDir.canonicalFile) &&
                                isRegularFileNoFollow(file) && file.length() in 1..(512L * 1024 * 1024)) { "Archivo de audio fuera de la cache privada" }
                            validateProgressiveDecode(file, requireNotNull(job))
                            "ok"
                        }
                        "download" -> {
                            validateYouTube(target)
                            val directory = File(requireNotNull(call.argument<String>("directory"))).canonicalFile
                            // Downloads remain inside app storage; export is performed separately via SAF.
                            require(isWithin(directory, filesDir.canonicalFile) || isWithin(directory, cacheDir.canonicalFile) || isWithin(directory, getExternalFilesDir(null)?.canonicalFile ?: filesDir.canonicalFile)) { "Destino fuera del almacenamiento de la app" }
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
                            val loopback = uri.scheme == "http" && uri.host == "127.0.0.1" &&
                                uri.port in 1..65535 && uri.userInfo == null && uri.query == null &&
                                uri.fragment == null && uri.path?.matches(Regex("/aurora-progressive/[a-f0-9]{64}")) == true
                            require(uri.scheme == "https" || loopback || File(input).isFile) { "Fuente de audio inválida" }
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
                            if (loopback) args.addAll(listOf("-rw_timeout", "120000000"))
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
            require(isWithin(cookies, filesDir.canonicalFile) && cookies.isFile && cookies.length() in 1..1048576) { "Archivo de sesión inválido" }
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
    private fun audioDuration(file: File): Long {
        val hasAudioTrack = try {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                (0 until extractor.trackCount).any { index ->
                    extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                }
            } finally { extractor.release() }
        } catch (_: Exception) { false }
        if (hasAudioTrack) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.absolutePath)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                if (duration > 0) return duration
            } catch (_: Exception) {
                // Fall back to the bundled ffprobe for formats Android's media APIs cannot inspect.
            } finally { retriever.release() }
        }
        return ffprobeAudioDuration(file)
    }
    private fun ffprobeAudioDuration(file: File): Long {
        val ffprobe = File(applicationInfo.nativeLibraryDir, "libffprobe.so")
        if (!ffprobe.isFile) throw IOException("No se encuentra el ffprobe integrado")
        val packages = File(noBackupFilesDir, "youtubedl-android/packages")
        val builder = ProcessBuilder(
            ffprobe.absolutePath, "-v", "error", "-select_streams", "a:0",
            "-show_entries", "stream=codec_type:format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", file.absolutePath,
        ).redirectErrorStream(true)
        builder.environment()["LD_LIBRARY_PATH"] = "${packages.absolutePath}/ffmpeg/usr/lib:${packages.absolutePath}/python/usr/lib"
        val text = runAudioCheck(builder, 30)
        val values = text.lineSequence().map(String::trim).filter(String::isNotEmpty).toList()
        if (values.size < 2 || values.first() != "audio") {
            throw IOException("El archivo no contiene una pista de audio")
        }
        val seconds = values.last().toDoubleOrNull()
        if (seconds == null || !seconds.isFinite() || seconds <= 0) {
            throw IOException("El audio no contiene una duración válida")
        }
        return (seconds * 1000).toLong()
    }
    private fun validateProgressiveDecode(file: File, jobId: String) {
        check(!cancelledDownloads.contains(jobId)) { "Descarga cancelada" }
        val builder = ProcessBuilder(
            File(applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath,
            "-nostdin", "-v", "error", "-xerror", "-err_detect", "explode",
            "-i", file.absolutePath, "-map", "0:a:0", "-vn", "-f", "null", "-",
        ).redirectErrorStream(true)
        val packages = File(noBackupFilesDir, "youtubedl-android/packages")
        builder.environment()["LD_LIBRARY_PATH"] = "${packages.absolutePath}/ffmpeg/usr/lib:${packages.absolutePath}/python/usr/lib"
        runAudioCheck(builder, 120, jobId)
        check(!cancelledDownloads.contains(jobId)) { "Descarga cancelada" }
    }
    private fun runAudioCheck(builder: ProcessBuilder, seconds: Long, jobId: String? = null): String {
        val process = builder.start()
        if (jobId != null) {
            validationProcesses[jobId] = process
            if (cancelledDownloads.contains(jobId)) process.destroy()
        }
        val output = FutureTask {
            process.inputStream.bufferedReader().use { reader ->
                val text = StringBuilder()
                val buffer = CharArray(512)
                while (true) {
                    val count = reader.read(buffer)
                    if (count < 0) break
                    if (text.length + count > 4096) throw IOException("La validacion de audio produjo demasiados errores")
                    text.append(buffer, 0, count)
                }
                if (process.waitFor() != 0) throw IOException("El audio no se puede validar completamente")
                text.toString()
            }
        }
        Thread(output, "aurora-audio-check").apply { isDaemon = true; start() }
        try {
            val text = output.get(seconds, TimeUnit.SECONDS)
            return text
        } catch (_: TimeoutException) {
            throw IOException("La validacion de audio tardo demasiado")
        } finally {
            if (jobId != null) validationProcesses.remove(jobId)
            process.destroy() // API 24 compatible; closing pipes also unblocks readers.
            output.cancel(true)
            try { process.inputStream.close() } catch (_: IOException) { }
            try { process.errorStream.close() } catch (_: IOException) { }
            try { process.outputStream.close() } catch (_: IOException) { }
        }
    }
    private fun isRegularFileNoFollow(file: File): Boolean = try {
        OsConstants.S_ISREG(Os.lstat(file.absolutePath).st_mode)
    } catch (_: Exception) { false }
    // Both arguments are canonical. The separator prevents sibling-prefix
    // escapes without File.toPath(), which is unavailable on API 24/25.
    private fun isWithin(file: File, directory: File): Boolean =
        file == directory || file.path.startsWith(directory.path + File.separator)
    private fun redact(message: String?): String = (message ?: "Error de audio").replace(Regex("https?://[^\\s<>\\\"']+")) { match ->
        try { Uri.parse(match.value).buildUpon().clearQuery().fragment(null).build().toString() }
        catch (_: Exception) { "[URL]" }
    }
}
