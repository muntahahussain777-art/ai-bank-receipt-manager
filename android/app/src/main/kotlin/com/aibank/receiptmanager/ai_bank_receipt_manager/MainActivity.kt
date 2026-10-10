package com.aibank.receiptmanager.ai_bank_receipt_manager

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Receives ACTION_SEND / SEND_MULTIPLE shares (e.g. WhatsApp screenshots)
 * and forwards file paths to Flutter over a MethodChannel / EventChannel.
 *
 * This is the supported Android Share Intent path. It does not scrape WhatsApp.
 */
class MainActivity : FlutterActivity() {
    private val methodChannelName = "ai_bank_receipt_manager/share"
    private val eventChannelName = "ai_bank_receipt_manager/share_events"

    private var eventSink: EventChannel.EventSink? = null
    private var initialShared: ArrayList<HashMap<String, String?>>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(true)
                    "getInitialShared" -> {
                        result.success(initialShared ?: arrayListOf<HashMap<String, String?>>())
                        initialShared = null
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent, isInitial = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent, isInitial = false)
    }

    private fun handleShareIntent(intent: Intent?, isInitial: Boolean) {
        if (intent == null) return
        val action = intent.action ?: return
        val files = ArrayList<HashMap<String, String?>>()

        when (action) {
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    copyUriToCache(uri, intent.type)?.let { files.add(it) }
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                uris?.forEach { uri ->
                    copyUriToCache(uri, intent.type)?.let { files.add(it) }
                }
            }
        }

        if (files.isEmpty()) return

        if (isInitial) {
            initialShared = files
        } else {
            eventSink?.success(files)
        }
    }

    private fun copyUriToCache(uri: Uri, mimeType: String?): HashMap<String, String?>? {
        return try {
            val resolver = applicationContext.contentResolver
            val name = uri.lastPathSegment ?: "shared_${System.currentTimeMillis()}"
            val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val outFile = File(cacheDir, "shared_$safeName")
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            } ?: return null

            hashMapOf(
                "path" to outFile.absolutePath,
                "mimeType" to (mimeType ?: resolver.getType(uri)),
                "displayName" to safeName,
                "uri" to uri.toString(),
            )
        } catch (_: Exception) {
            null
        }
    }
}
