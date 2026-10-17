package com.aurora.aurora_music

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal `aurora/updater`: abre el instalador del sistema con un APK ya
 * verificado por Dart. El APK debe firmarse siempre con la misma keystore o
 * Android rechazará la actualización.
 */
class AuroraApkInstaller : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "aurora/updater").also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "canInstall" -> result.success(context.packageManager.canRequestPackageInstalls())
            "openInstallSettings" -> {
                startNew(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
                result.success(null)
            }
            "install" -> {
                val path = call.argument<String>("path") ?: return result.error("path", "Falta la ruta.", null)
                val file = File(path)
                // Solo APK dentro del directorio temporal de la app.
                if (!file.canonicalFile.startsWith(context.cacheDir.canonicalFile) || file.extension != "apk" || !file.isFile) {
                    return result.error("path", "APK no válido.", null)
                }
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
                startNew(
                    Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startNew(intent: Intent) =
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
