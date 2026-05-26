package com.addabenattia.addalocation

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "adda_location/incoming_file"
    private var methodChannel: MethodChannel? = null
    private var pendingFilePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "consumePending") {
                val p = pendingFilePath
                pendingFilePath = null
                result.success(p)
            } else {
                result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW, Intent.ACTION_SEND -> intent.data ?: intent.clipData?.getItemAt(0)?.uri
            else -> null
        }
        if (uri == null) return
        val localPath = resolveToLocalPath(uri) ?: return
        val ch = methodChannel
        if (ch != null) {
            ch.invokeMethod("fileOpened", mapOf("path" to localPath))
        } else {
            pendingFilePath = localPath
        }
    }

    /// Content URIs ne sont pas des chemins fichiers — on copie dans le cache.
    private fun resolveToLocalPath(uri: Uri): String? {
        return try {
            if (uri.scheme == "file") {
                uri.path
            } else {
                val suffix = suffixFor(uri)
                val file = File(cacheDir, "incoming_${System.currentTimeMillis()}$suffix")
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(file).use { output -> input.copyTo(output) }
                }
                file.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun suffixFor(uri: Uri): String {
        val last = uri.lastPathSegment ?: return ".bin"
        return when {
            last.endsWith(".adls", ignoreCase = true) -> ".adls"
            last.endsWith(".adlb", ignoreCase = true) -> ".adlb"
            else -> ".bin"
        }
    }
}
