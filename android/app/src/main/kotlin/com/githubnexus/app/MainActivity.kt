package com.githubnexus.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val SHARE_METHOD_CHANNEL = "com.githubnexus.app/share_intent"
        private const val SHARE_EVENT_CHANNEL = "com.githubnexus.app/share_intent_stream"

        private const val DEPLOY_METHOD_CHANNEL = "com.githubnexus.app/deploy_service"
        private const val DEPLOY_EVENT_CHANNEL = "com.githubnexus.app/deploy_service_events"

        private const val REQ_POST_NOTIFICATIONS = 4101
        private const val MAX_SHARED_BYTES = 105L * 1024L * 1024L // 105 MB safety ceiling
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var shareEventSink: EventChannel.EventSink? = null
    private var deployEventSink: EventChannel.EventSink? = null
    private var pendingSharedPayload: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent, notifyLiveStream = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, notifyLiveStream = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // --- Phase 3: Share Intent Bridge ---
        MethodChannel(messenger, SHARE_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedZip" -> {
                    val payload = pendingSharedPayload
                    pendingSharedPayload = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, SHARE_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            }
        )

        // --- Phase 4: Foreground Deploy Service Bridge ---
        MethodChannel(messenger, DEPLOY_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    ensureNotificationPermission()
                    result.success(true)
                }

                "startForegroundDeploy" -> {
                    ensureNotificationPermission()
                    val title = call.argument<String>("title") ?: "GitHub Nexus Deploy"
                    val subtitle = call.argument<String>("subtitle") ?: "Initializing..."
                    val svcIntent = Intent(this, DeployForegroundService::class.java).apply {
                        action = DeployForegroundService.ACTION_START
                        putExtra(DeployForegroundService.EXTRA_TITLE, title)
                        putExtra(DeployForegroundService.EXTRA_SUBTITLE, subtitle)
                    }
                    startDeployServiceCompat(svcIntent)
                    result.success(true)
                }

                "updateForegroundProgress" -> {
                    val title = call.argument<String>("title") ?: "GitHub Nexus Deploy"
                    val subtitle = call.argument<String>("subtitle") ?: "Uploading..."
                    val progress = call.argument<Int>("progress") ?: 0
                    val svcIntent = Intent(this, DeployForegroundService::class.java).apply {
                        action = DeployForegroundService.ACTION_UPDATE
                        putExtra(DeployForegroundService.EXTRA_TITLE, title)
                        putExtra(DeployForegroundService.EXTRA_SUBTITLE, subtitle)
                        putExtra(DeployForegroundService.EXTRA_PROGRESS, progress)
                    }
                    startService(svcIntent)
                    result.success(true)
                }

                "finishForegroundDeploy" -> {
                    val title = call.argument<String>("title") ?: "Deployment Complete"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val success = call.argument<Boolean>("success") ?: true
                    val svcIntent = Intent(this, DeployForegroundService::class.java).apply {
                        action = DeployForegroundService.ACTION_FINISH
                        putExtra(DeployForegroundService.EXTRA_TITLE, title)
                        putExtra(DeployForegroundService.EXTRA_SUBTITLE, subtitle)
                        putExtra(DeployForegroundService.EXTRA_SUCCESS, success)
                    }
                    startService(svcIntent)
                    result.success(true)
                }

                "stopForegroundDeploy" -> {
                    val svcIntent = Intent(this, DeployForegroundService::class.java).apply {
                        action = DeployForegroundService.ACTION_STOP
                    }
                    startService(svcIntent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, DEPLOY_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    deployEventSink = events
                    DeployForegroundService.onCancelRequested = {
                        mainHandler.post {
                            deployEventSink?.success(mapOf("event" to "cancel_requested"))
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    deployEventSink = null
                    DeployForegroundService.onCancelRequested = null
                }
            }
        )
    }

    private fun startDeployServiceCompat(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            // Fallback gracefully if OS temporarily denies foreground launch.
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_POST_NOTIFICATIONS
                )
            }
        }
    }

    private fun handleIncomingIntent(intent: Intent?, notifyLiveStream: Boolean) {
        if (intent == null) return
        val uri: Uri = when (intent.action) {
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        } ?: return

        ioExecutor.execute {
            val payload = copyUriToCacheSafely(uri) ?: return@execute
            mainHandler.post {
                if (notifyLiveStream && shareEventSink != null) {
                    shareEventSink?.success(payload)
                } else {
                    pendingSharedPayload = payload
                }
            }
        }
    }

    private fun copyUriToCacheSafely(uri: Uri): Map<String, Any>? {
        return try {
            val displayName = resolveDisplayName(uri) ?: "shared_archive.zip"
            val sanitizedName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val targetDir = File(cacheDir, "shared_zips").apply {
                if (!exists()) mkdirs()
                listFiles()?.forEach { old ->
                    if (System.currentTimeMillis() - old.lastModified() > 3_600_000L) {
                        old.delete()
                    }
                }
            }

            val outFile = File(targetDir, "${System.currentTimeMillis()}_$sanitizedName")
            var totalBytes = 0L
            val header = ByteArray(4)
            var headerBytesRead = 0

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        if (headerBytesRead < 4) {
                            val toCopy = minOf(read, 4 - headerBytesRead)
                            System.arraycopy(buffer, 0, header, headerBytesRead, toCopy)
                            headerBytesRead += toCopy
                        }
                        totalBytes += read
                        if (totalBytes > MAX_SHARED_BYTES) {
                            outFile.delete()
                            return mapOf(
                                "error" to "حجم الملف المشارك يتجاوز الحد الأقصى المسموح (100MB)."
                            )
                        }
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            } ?: return null

            val isZipSignature = headerBytesRead >= 4 &&
                header[0] == 0x50.toByte() &&
                header[1] == 0x4B.toByte() &&
                ((header[2] == 0x03.toByte() && header[3] == 0x04.toByte()) ||
                    (header[2] == 0x05.toByte() && header[3] == 0x06.toByte()))

            if (!isZipSignature && !displayName.lowercase().endsWith(".zip")) {
                outFile.delete()
                return mapOf(
                    "error" to "الملف المشارك ليس أرشيف ZIP صالحاً."
                )
            }

            mapOf(
                "path" to outFile.absolutePath,
                "name" to displayName,
                "size" to totalBytes
            )
        } catch (e: Exception) {
            mapOf("error" to "تعذر قراءة الملف المشارك: ${e.localizedMessage ?: "خطأ غير معروف"}")
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = cursor.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/')
    }

    override fun onDestroy() {
        DeployForegroundService.onCancelRequested = null
        ioExecutor.shutdownNow()
        super.onDestroy()
    }
}
