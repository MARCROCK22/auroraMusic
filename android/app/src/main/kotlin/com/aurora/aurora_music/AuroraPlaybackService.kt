package com.aurora.aurora_music

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/** One native player. Flutter owns the queue, repeat, shuffle and track resolution. */
@UnstableApi
class AuroraPlaybackService : MediaSessionService() {
    companion object { const val BIND_AUDIO = "com.aurora.aurora_music.BIND_AUDIO" }
    inner class AudioBinder : Binder() { val service get() = this@AuroraPlaybackService }
    private lateinit var player: ExoPlayer
    private var session: MediaSession? = null
    private val main = Handler(Looper.getMainLooper())
    var eventSink: ((Map<String, Any?>) -> Unit)? = null
    private var generation = 0L
    private var expectedDuration = 0L
    private var completed = false
    private var failure: String? = null
    private var metadata = MediaMetadata.EMPTY
    private val progress = object : Runnable {
        override fun run() {
            publishState()
            main.postDelayed(this, 250)
        }
    }

    override fun onCreate() {
        super.onCreate()
        player = ExoPlayer.Builder(this).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
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
        val queuePlayer = object : ForwardingSimpleBasePlayer(player) {
            override fun getState(): State = super.getState().buildUpon()
                .setAvailableCommands(super.getState().availableCommands.buildUpon()
                    .addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                        Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                    .remove(Player.COMMAND_CHANGE_MEDIA_ITEMS)
                    .remove(Player.COMMAND_SET_MEDIA_ITEM)
                    .build()).build()

            override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
                when (seekCommand) {
                    Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> emit("action", mapOf("action" to "next"))
                    Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> emit("action", mapOf("action" to "previous"))
                    else -> return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
                }
                return Futures.immediateVoidFuture()
            }
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        session = MediaSession.Builder(this, queuePlayer).apply {
            if (launch != null) setSessionActivity(PendingIntent.getActivity(this@AuroraPlaybackService,
                0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }.build()
        // Our Flutter bridge uses a local Binder rather than MediaController.
        // Register explicitly so the service creates notifications/foreground state.
        addSession(session!!)
        main.post(progress)
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == BIND_AUDIO) AudioBinder() else super.onBind(intent)

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        if (controllerInfo.packageName == packageName || controllerInfo.isTrusted) session else null

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
        player.pause()
        player.stop()
        generation = nextGeneration
        expectedDuration = duration
        completed = false
        failure = null
        val uri = if (parsed.scheme == null) Uri.fromFile(java.io.File(input)) else parsed
        val http = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(false)
        val factory = DefaultMediaSourceFactory(DefaultDataSource.Factory(this, http))
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
            .setArtist(arguments["artist"] as? String).setArtworkUri(artwork).build()
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
                player.volume = value.coerceIn(0f, 1f)
            }
            "metadata" -> updateMetadata(arguments)
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
        "volume" to player.volume.toDouble(), "error" to failure,
    )
    private fun publishState() { eventSink?.invoke(state()) }
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
        main.removeCallbacks(progress)
        eventSink = null
        session?.release()
        session = null
        player.release()
        super.onDestroy()
    }
}
