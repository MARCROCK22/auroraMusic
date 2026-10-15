package com.aurora.aurora_music

import android.app.PendingIntent
import android.content.Intent
import android.content.Context
import android.media.AudioManager
import android.media.audiofx.Equalizer
import android.media.audiofx.AudioEffect
import android.net.Uri
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.media3.common.SimpleBasePlayer
import android.net.wifi.WifiManager
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt
import java.util.concurrent.atomic.AtomicLong

/** One native player. Flutter owns the queue, repeat, shuffle and track resolution. */
@UnstableApi
class AuroraPlaybackService : MediaSessionService() {
    companion object {
        const val BIND_AUDIO = "com.aurora.aurora_music.BIND_AUDIO"
        @Volatile var playbackActive = false
            private set
    }
    inner class AudioBinder : Binder() { val service get() = this@AuroraPlaybackService }
    private lateinit var player: ExoPlayer
    private lateinit var sessionPlayer: SessionPlayer
    /** Playback owned by the hidden YouTube Music WebView, mirrored into the session. */
    private data class External(val playing: Boolean, val buffering: Boolean,
        val positionMs: Long, val durationMs: Long)
    private var external: External? = null
    private val webWakeLock by lazy {
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aurora:web-playback").apply { setReferenceCounted(false) }
    }
    @Suppress("DEPRECATION")
    private val webWifiLock by lazy {
        (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
            .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "aurora:web-playback").apply { setReferenceCounted(false) }
    }
    private var session: MediaSession? = null
    private val main = Handler(Looper.getMainLooper())
    var eventSink: ((Map<String, Any?>) -> Unit)? = null
    private var generation = 0L
    private var expectedDuration = 0L
    private var completed = false
    private var failure: String? = null
    private var metadata = MediaMetadata.EMPTY
    private var networkBytes = AtomicLong(0)
    private var networkRequests = AtomicLong(0)
    private var equalizer: Equalizer? = null
    private var userVolume = 0.8f
    private var preamp = 1f
    // The eight UI controls form a curve mapped onto the device's native bands.
    private val eqFrequencies = listOf(60.0, 170.0, 310.0, 600.0, 1000.0, 3000.0, 6000.0, 12000.0)
    private val progress = object : Runnable {
        override fun run() {
            publishState()
            main.postDelayed(this, 250)
        }
    }

    override fun onCreate() {
        super.onCreate()
        player = ExoPlayer.Builder(this).setLoadControl(androidx.media3.exoplayer.DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 30000, 1500, 3000)
            .setTargetBufferBytes(8 * 1024 * 1024).setPrioritizeTimeOverSizeThresholds(false).build()).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            setHandleAudioBecomingNoisy(true)
            // Streams need the Wi-Fi lock too, or screen-off playback stalls; ExoPlayer releases both when not playing.
            setWakeMode(C.WAKE_MODE_NETWORK)
            volume = 0.8f
            addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) { publishState() }
                override fun onPlayerError(error: PlaybackException) {
                    // Do not expose signed stream URLs, request headers or native exception causes.
                    val status = generateSequence(error as Throwable) { it.cause }
                        .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
                        .firstOrNull()?.responseCode?.let { "; HTTP $it" } ?: ""
                    failure = "No se pudo reproducir el audio (${error.errorCodeName}$status)."
                    emit("error", mapOf("message" to failure))
                    publishState()
                }
                override fun onPlaybackStateChanged(state: Int) {
                    if (state != Player.STATE_ENDED || completed || failure != null) return
                    completed = true
                    val duration = player.duration.takeIf { it > 0 } ?: expectedDuration
                    if (duration > 0 && player.currentPosition + 2000 < duration) {
                        failure = "El audio termino antes de completar la reproduccion."
                        emit("error", mapOf("message" to failure))
                    } else emit("completed")
                    publishState()
                }
            })
        }
        initializeEqualizer()
        sessionPlayer = SessionPlayer(player)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        session = MediaSession.Builder(this, sessionPlayer).apply {
            if (launch != null) setSessionActivity(PendingIntent.getActivity(this@AuroraPlaybackService,
                0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }.build()
        // Our Flutter bridge uses a local Binder rather than MediaController.
        // Register explicitly so the service creates notifications/foreground state.
        addSession(session!!)
        main.post(progress)
    }

    /** Flutter owns the queue: transport commands become actions for the controller. */
    private inner class SessionPlayer(player: Player) : ForwardingSimpleBasePlayer(player) {
        fun refresh() = invalidateState()

        override fun getState(): State {
            val base = super.getState()
            val commands = base.availableCommands.buildUpon()
                .addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                    Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                .remove(Player.COMMAND_CHANGE_MEDIA_ITEMS)
                .remove(Player.COMMAND_SET_MEDIA_ITEM)
            val web = external ?: return base.buildUpon().setAvailableCommands(commands.build()).build()
            commands.addAll(Player.COMMAND_PLAY_PAUSE, Player.COMMAND_STOP, Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_CURRENT_MEDIA_ITEM, Player.COMMAND_GET_METADATA, Player.COMMAND_GET_TIMELINE)
            val item = SimpleBasePlayer.MediaItemData.Builder("aurora-web")
                .setMediaItem(MediaItem.Builder().setMediaId("aurora-web").setMediaMetadata(metadata).build())
                .setMediaMetadata(metadata)
                .setDurationUs(if (web.durationMs > 0) web.durationMs * 1000 else C.TIME_UNSET)
                .setIsSeekable(web.durationMs > 0)
                .build()
            return base.buildUpon().setAvailableCommands(commands.build())
                .setPlaylist(listOf(item)).setCurrentMediaItemIndex(0)
                .setPlayWhenReady(web.playing || web.buffering, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
                .setPlaybackState(if (web.buffering) Player.STATE_BUFFERING else Player.STATE_READY)
                .setIsLoading(false)
                .setContentPositionMs(web.positionMs)
                .build()
        }

        override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
            when (seekCommand) {
                Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> emit("action", mapOf("action" to "next"))
                Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> emit("action", mapOf("action" to "previous"))
                else -> if (external != null) {
                    emit("action", mapOf("action" to "seek", "positionMs" to positionMs.coerceAtLeast(0L)))
                } else return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
            }
            return Futures.immediateVoidFuture()
        }
        override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
            emit("action", mapOf("action" to if (playWhenReady) "play" else "pause"))
            return Futures.immediateVoidFuture()
        }
        override fun handleStop(): ListenableFuture<*> {
            emit("action", mapOf("action" to "stop"))
            return Futures.immediateVoidFuture()
        }
    }

    /** A playing WebView needs the same locks ExoPlayer takes for its own streams. */
    private fun setExternal(arguments: Map<*, *>) {
        external = if (arguments["active"] != true) null else External(
            playing = arguments["playing"] == true,
            buffering = arguments["buffering"] == true,
            positionMs = ((arguments["positionMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
            durationMs = ((arguments["durationMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
        )
        val web = external
        if (web != null && (web.playing || web.buffering)) {
            // Renewed with every update; expires on its own if Flutter stops reporting.
            webWakeLock.acquire(10 * 60 * 1000L)
            webWifiLock.acquire()
        } else releaseWebLocks()
        sessionPlayer.refresh()
    }

    private fun releaseWebLocks() {
        if (webWakeLock.isHeld) webWakeLock.release()
        if (webWifiLock.isHeld) webWifiLock.release()
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == BIND_AUDIO) AudioBinder() else super.onBind(intent)

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        if (controllerInfo.packageName == packageName || controllerInfo.isTrusted) session else null

    private fun initializeEqualizer() {
        var candidate: Equalizer? = null
        try {
            val sessionId = (getSystemService(Context.AUDIO_SERVICE) as AudioManager).generateAudioSessionId()
            check(sessionId > 0) // Never attach an effect to the deprecated global session 0.
            player.setAudioSessionId(sessionId)
            candidate = Equalizer(0, sessionId)
            check(candidate.numberOfBands > 0 && candidate.hasControl())
            check(candidate.setEnabled(false) == AudioEffect.SUCCESS)
            equalizer = candidate
        } catch (_: Exception) {
            candidate?.release()
            equalizer = null
        }
    }

    private fun setEqualizer(arguments: Map<*, *>) {
        val enabled = arguments["enabled"] == true
        val gains = (arguments["gainsDb"] as? List<*>)?.map {
            require(it is Number && it.toDouble().isFinite()) { "Ganancia invalida" }
            it.toDouble().coerceIn(-12.0, 12.0)
        } ?: emptyList()
        require(gains.size == eqFrequencies.size) { "Bandas de ecualizador invalidas" }
        val effect = equalizer ?: return
        try {
            check(effect.hasControl())
            if (!enabled) {
                check(effect.setEnabled(false) == AudioEffect.SUCCESS)
                preamp = 1f
            } else {
                val range = effect.bandLevelRange
                val levels = (0 until effect.numberOfBands).map { band ->
                    val frequency = effect.getCenterFreq(band.toShort()) / 1000.0
                    val upper = eqFrequencies.indexOfFirst { it >= frequency }
                    val gain = when {
                        upper == 0 -> gains.first()
                        upper < 0 -> gains.last()
                        else -> {
                            val fraction = (ln(frequency) - ln(eqFrequencies[upper - 1])) /
                                (ln(eqFrequencies[upper]) - ln(eqFrequencies[upper - 1]))
                            gains[upper - 1] + (gains[upper] - gains[upper - 1]) * fraction
                        }
                    }
                    (gain * 100).roundToInt().coerceIn(range[0].toInt(), range[1].toInt()).toShort()
                }
                // Attenuate before enabling boosted bands, preserving the requested user volume.
                preamp = 10.0.pow(-(levels.maxOrNull()?.toInt() ?: 0).coerceAtLeast(0) / 2000.0).toFloat()
                player.volume = userVolume * preamp
                levels.forEachIndexed { band, level -> effect.setBandLevel(band.toShort(), level) }
                check(effect.setEnabled(true) == AudioEffect.SUCCESS)
            }
        } catch (_: Exception) {
            effect.release()
            equalizer = null
            preamp = 1f
        }
        player.volume = userVolume * preamp
    }

    fun load(arguments: Map<*, *>) {
        val input = arguments["input"] as? String ?: throw IllegalArgumentException("Audio requerido")
        require(input.isNotBlank() && !input.contains('\n') && !input.contains('\r')) { "Audio invalido" }
        val parsed = Uri.parse(input)
        require(parsed.scheme in listOf(null, "https", "file", "content")) { "Protocolo de audio no permitido" }
        if (parsed.scheme == "https") require(!parsed.host.isNullOrBlank() && parsed.userInfo == null) { "URL de audio invalida" }
        val headers = (arguments["headers"] as? Map<*, *> ?: emptyMap<Any, Any>()).entries.associate { (key, value) ->
            require(key is String && value is String && key.matches(Regex("[!#$%&'*+.^_`|~0-9A-Za-z-]+")) &&
                !value.contains('\r') && !value.contains('\n')) { "Cabecera invalida" }
            key to value
        }
        val nextGeneration = (arguments["generation"] as? Number)?.toLong() ?: throw IllegalArgumentException("Generacion requerida")
        val start = ((arguments["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
        val duration = ((arguments["durationMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
        // Validate all inputs before replacing the currently playable source.
        if (external != null) {
            external = null
            releaseWebLocks()
            sessionPlayer.refresh()
        }
        player.pause()
        player.stop()
        generation = nextGeneration
        expectedDuration = duration
        completed = false
        failure = null
        networkBytes = AtomicLong(0)
        networkRequests = AtomicLong(0)
        val transferred = networkBytes
        val requests = networkRequests
        val uri = if (parsed.scheme == null) Uri.fromFile(java.io.File(input)) else parsed
        val http = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(false)
        val transfer = object : TransferListener {
            override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {}
            override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) { if (isNetwork) requests.incrementAndGet() }
            override fun onBytesTransferred(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int) { if (isNetwork) transferred.addAndGet(bytesTransferred.toLong()) }
            override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) {}
        }
        val factory = DefaultMediaSourceFactory(DefaultDataSource.Factory(this, http).setTransferListener(transfer))
            .setLoadErrorHandlingPolicy(object : DefaultLoadErrorHandlingPolicy(1) {
                override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
                    val denied = generateSequence(info.exception as Throwable) { it.cause }
                        .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
                        .any { it.responseCode == 403 || it.responseCode == 429 }
                    return if (denied) C.TIME_UNSET else super.getRetryDelayMsFor(info)
                }
            })
        val item = MediaItem.Builder().setMediaId("aurora-$generation").setUri(uri)
            .setMediaMetadata(metadata).build()
        player.setMediaSource(factory.createMediaSource(item), start)
        player.prepare()
        publishState()
    }

    fun updateMetadata(arguments: Map<*, *>) {
        val artwork = (arguments["artworkUrl"] as? String)?.let { Uri.parse(it) }
        require(artwork == null || artwork.scheme == "https") { "Portada invalida" }
        metadata = MediaMetadata.Builder().setTitle(arguments["title"] as? String ?: "Aurora")
            .setArtist(arguments["artist"] as? String).setAlbumTitle(arguments["album"] as? String)
            .setDurationMs(((arguments["durationMs"] as? Number)?.toLong() ?: 0L).takeIf { it > 0 })
            .setArtworkUri(artwork).build()
        if (external != null) sessionPlayer.refresh()
        player.currentMediaItem?.let { current ->
            player.replaceMediaItem(0, current.buildUpon().setMediaMetadata(metadata).build())
        }
    }

    fun command(method: String, arguments: Map<*, *>): Any? {
        when (method) {
            "load" -> load(arguments)
            "play" -> { if (player.mediaItemCount > 0) player.play() }
            "pause" -> player.pause()
            "stop" -> {
                player.pause()
                player.stop()
                player.clearMediaItems()
                generation = (arguments["generation"] as? Number)?.toLong() ?: generation + 1
                expectedDuration = 0
                failure = null
                completed = false
            }
            "seek" -> player.seekTo(((arguments["positionMs"] as? Number)?.toLong() ?: 0L)
                .coerceAtLeast(0).let { if (player.duration > 0) it.coerceAtMost(player.duration) else it })
            "volume" -> {
                val value = (arguments["volume"] as? Number)?.toFloat() ?: throw IllegalArgumentException("Volumen requerido")
                require(value.isFinite()) { "Volumen invalido" }
                userVolume = value.coerceIn(0f, 1f)
                player.volume = userVolume * preamp
            }
            "equalizer" -> setEqualizer(arguments)
            "metadata" -> updateMetadata(arguments)
            "external" -> setExternal(arguments)
            "state", "initialize" -> return state()
            else -> throw IllegalArgumentException("Comando no permitido")
        }
        publishState()
        return null
    }

    fun state(): Map<String, Any?> = mapOf(
        "type" to "state", "generation" to generation, "playing" to player.isPlaying,
        "buffering" to (player.playbackState == Player.STATE_BUFFERING),
        "positionMs" to player.currentPosition.coerceAtLeast(0L),
        "durationMs" to (player.duration.takeIf { it > 0L } ?: expectedDuration),
        "volume" to userVolume.toDouble(), "error" to failure,
        "supportsEqualizer" to (equalizer != null),
        "eqFrequencies" to (if (equalizer != null) eqFrequencies else emptyList<Double>()),
        "audioNetworkRequests" to networkRequests.get(), "audioNetworkBytes" to networkBytes.get(),
    )
    private fun publishState() {
        playbackActive = player.playWhenReady || player.isPlaying || player.playbackState == Player.STATE_BUFFERING ||
            external?.let { it.playing || it.buffering } == true
        eventSink?.invoke(state())
    }
    private fun emit(type: String, extra: Map<String, Any?> = emptyMap()) {
        eventSink?.invoke(mapOf("type" to type, "generation" to generation) + extra)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Flutter owns queue transitions, so preserve its engine while audio is ongoing.
        if (!isPlaybackOngoing) {
            player.pause()
            stopSelf()
        }
    }

    override fun onDestroy() {
        playbackActive = false
        main.removeCallbacks(progress)
        releaseWebLocks()
        eventSink = null
        session?.release()
        session = null
        equalizer?.release()
        equalizer = null
        player.release()
        super.onDestroy()
    }
}
