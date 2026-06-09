package com.addabenattia.addalocation

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "adda_location/incoming_file"
    private val safChannelName = "adda_location/saf"
    private val reqPickDir = 0xADDA
    private var methodChannel: MethodChannel? = null
    private var safChannel: MethodChannel? = null
    private var pendingFilePath: String? = null
    private var pendingPickResult: MethodChannel.Result? = null

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

        safChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannelName)
        safChannel?.setMethodCallHandler { call, result -> handleSaf(call, result) }

        handleIntent(intent)
    }

    // ───────────────────── Storage Access Framework ─────────────────────
    // Écriture conforme Play Store dans un dossier choisi par l'utilisateur
    // (sauvegardes cloud), via une URI d'arborescence à permission persistante.

    private fun treeDoc(treeUri: String): DocumentFile? =
        DocumentFile.fromTreeUri(this, Uri.parse(treeUri))

    private fun handleSaf(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> {
                if (pendingPickResult != null) {
                    result.success(null)
                    return
                }
                pendingPickResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                            or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                startActivityForResult(intent, reqPickDir)
            }
            "isAccessible" -> {
                val uri = call.argument<String>("uri")
                result.success(uri != null && treeDoc(uri)?.canWrite() == true)
            }
            "writeFile" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                val bytes = call.argument<ByteArray>("bytes")
                if (uri == null || name == null || bytes == null) {
                    result.error("BAD_ARGS", "uri/name/bytes manquants", null); return
                }
                try {
                    val tree = treeDoc(uri) ?: throw Exception("Dossier inaccessible")
                    tree.findFile(name)?.delete()
                    val doc = tree.createFile("application/octet-stream", name)
                        ?: throw Exception("Création du fichier impossible")
                    contentResolver.openOutputStream(doc.uri)?.use { it.write(bytes) }
                        ?: throw Exception("Écriture impossible")
                    result.success(doc.uri.toString())
                } catch (e: Exception) {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }
            "listFiles" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) { result.error("BAD_ARGS", "uri manquant", null); return }
                try {
                    val tree = treeDoc(uri) ?: throw Exception("Dossier inaccessible")
                    val files = tree.listFiles()
                        .filter { it.isFile }
                        .map {
                            mapOf(
                                "name" to (it.name ?: ""),
                                "modified" to it.lastModified(),
                                "size" to it.length()
                            )
                        }
                    result.success(files)
                } catch (e: Exception) {
                    result.error("LIST_FAILED", e.message, null)
                }
            }
            "readFile" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                if (uri == null || name == null) {
                    result.error("BAD_ARGS", "uri/name manquants", null); return
                }
                try {
                    val tree = treeDoc(uri) ?: throw Exception("Dossier inaccessible")
                    val doc = tree.findFile(name) ?: throw Exception("Fichier introuvable")
                    val bytes = contentResolver.openInputStream(doc.uri)?.use { it.readBytes() }
                        ?: throw Exception("Lecture impossible")
                    result.success(bytes)
                } catch (e: Exception) {
                    result.error("READ_FAILED", e.message, null)
                }
            }
            "deleteFile" -> {
                val uri = call.argument<String>("uri")
                val name = call.argument<String>("name")
                if (uri == null || name == null) {
                    result.error("BAD_ARGS", "uri/name manquants", null); return
                }
                try {
                    treeDoc(uri)?.findFile(name)?.delete()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqPickDir) {
            val r = pendingPickResult
            pendingPickResult = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: Exception) {}
                val name = DocumentFile.fromTreeUri(this, uri)?.name ?: ""
                r?.success(mapOf("uri" to uri.toString(), "name" to name))
            } else {
                r?.success(null)
            }
        }
    }

    // ───────────────────── Fichiers entrants (.adls / .adlb) ─────────────

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
