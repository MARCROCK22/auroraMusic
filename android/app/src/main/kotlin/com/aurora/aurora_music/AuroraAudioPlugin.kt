package com.aurora.aurora_music

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** An engine plugin keeps playback independent of the Activity's lifetime. */
@UnstableApi
class AuroraAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var service: AuroraPlaybackService? = null
    private var bound = false
    private val pendingInitialization = mutableListOf<MethodChannel.Result>()
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            service = (binder as AuroraPlaybackService.AudioBinder).service.also { playback ->
                playback.eventSink = { event -> sink?.success(event) }
            }
            val state = service!!.state()
            pendingInitialization.toList().also { pendingInitialization.clear() }
                .forEach { it.success(state) }
            sink?.success(state)
        }
        override fun onServiceDisconnected(name: ComponentName) {
            service = null
            sink?.error("AUDIO_DISCONNECTED", "El servicio de audio se desconecto.", null)
            pendingInitialization.toList().also { pendingInitialization.clear() }
                .forEach { it.error("AUDIO_DISCONNECTED", "El servicio de audio se desconecto.", null) }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "aurora/audio").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "aurora/audio/events").also { it.setStreamHandler(this) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "initialize" && service == null) {
            pendingInitialization.add(result)
            if (!bound) {
                try {
                    bound = context.bindService(Intent(context, AuroraPlaybackService::class.java)
                        .setAction(AuroraPlaybackService.BIND_AUDIO), connection, Context.BIND_AUTO_CREATE)
                    check(bound) { "No se pudo iniciar el servicio de audio." }
                } catch (_: Exception) {
                    pendingInitialization.toList().also { pendingInitialization.clear() }
                        .forEach { it.error("AUDIO_ERROR", "No se pudo iniciar el servicio de audio.", null) }
                }
            }
            return
        }
        if (call.method == "dispose") {
            disconnect(stop = true)
            result.success(null)
            return
        }
        val playback = service
        if (playback == null) {
            result.error("AUDIO_NOT_INITIALIZED", "El servicio de audio no esta preparado.", null)
            return
        }
        try {
            result.success(playback.command(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
        } catch (_: IllegalArgumentException) {
            result.error("AUDIO_INPUT", "Entrada de audio invalida.", null)
        } catch (_: Exception) {
            result.error("AUDIO_ERROR", "No se pudo ejecutar el comando de audio.", null)
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        service?.state()?.let { sink?.success(it) }
    }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun disconnect(stop: Boolean) {
        service?.let {
            it.eventSink = null
            if (stop) { it.command("stop", emptyMap<Any, Any>()); it.stopSelf() }
        }
        service = null
        if (bound) context.unbindService(connection)
        bound = false
        pendingInitialization.toList().also { pendingInitialization.clear() }
            .forEach { it.error("AUDIO_DISPOSED", "El servicio de audio se cerro.", null) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        disconnect(stop = true)
    }
}
