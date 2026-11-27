package com.zapi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.zapi.chat/background_notifications"
        private const val MEDIA_BRIDGE_CHANNEL = "com.zapi.chat/media_bridge"
        private const val REQUEST_PICK_DOCUMENT = 9412
        private const val REQUEST_DEVICE_AUTH = 9413
    }

    private var methodChannel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var pendingChatId: String? = null
    private var pendingDocResult: MethodChannel.Result? = null
    private var pendingDocMaxBytes: Long = 680L * 1024L
    private var pendingAuthResult: MethodChannel.Result? = null
    private val ioExecutor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureChatIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val chatId = intent.getStringExtra(ZapiMessageNotifier.EXTRA_CHAT_ID)
        if (!chatId.isNullOrEmpty()) {
            if (methodChannel != null) {
                methodChannel?.invokeMethod("openChat", chatId)
            } else {
                pendingChatId = chatId
            }
        }
    }

    override fun onResume() {
        super.onResume()
        ZapiMessageNotifier.setAppForeground(this, true)
    }

    override fun onPause() {
        ZapiMessageNotifier.setAppForeground(this, false)
        super.onPause()
    }

    override fun onDestroy() {
        ZapiMessageNotifier.setAppForeground(this, false)
        ZapiMessageNotifier.setActiveChatId(this, null)
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_DOCUMENT) {
            val result = pendingDocResult
            val maxBytes = pendingDocMaxBytes
            pendingDocResult = null
            if (result == null) return

            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (uri == null) {
                result.success(null)
                return
            }

            ioExecutor.execute {
                try {
                    val payload = inspectAndCopyDocument(uri, maxBytes)
                    mainHandler.post { result.success(payload) }
                } catch (e: Exception) {
                    mainHandler.post {
                        result.error("DOC_PICK_ERROR", e.localizedMessage ?: "Falha ao ler o arquivo.", null)
                    }
                }
            }
            return
        }
        if (requestCode == REQUEST_DEVICE_AUTH) {
            val result = pendingAuthResult
            pendingAuthResult = null
            result?.success(resultCode == Activity.RESULT_OK)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    ZapiMessageNotifier.setBackgroundEnabled(this, true)
                    startBackgroundMessageService()
                    ZapiMessageNotifier.schedulePeriodicSyncJob(this)
                    result.success(true)
                }

                "stopBackgroundService" -> {
                    ZapiMessageNotifier.setBackgroundEnabled(this, false)
                    stopBackgroundMessageService()
                    ZapiMessageNotifier.cancelPeriodicSyncJob(this)
                    result.success(true)
                }

                "pauseBackgroundServiceOnLogout" -> {
                    stopBackgroundMessageService()
                    ZapiMessageNotifier.cancelPeriodicSyncJob(this)
                    result.success(true)
                }

                "isBackgroundServiceRunning" -> {
                    result.success(ZapiMessageService.isRunning)
                }

                "isBackgroundEnabled" -> {
                    result.success(ZapiMessageNotifier.isBackgroundEnabled(this))
                }

                "setAppForeground" -> {
                    val isForeground = call.argument<Boolean>("isForeground") ?: false
                    ZapiMessageNotifier.setAppForeground(this, isForeground)
                    result.success(null)
                }

                "setActiveChatId" -> {
                    val chatId = call.argument<String>("chatId")
                    ZapiMessageNotifier.setActiveChatId(this, chatId)
                    result.success(null)
                }

                "markMessageNotified" -> {
                    val chatId = call.argument<String>("chatId")
                    val messageId = call.argument<String>("messageId")
                    if (!chatId.isNullOrEmpty() && !messageId.isNullOrEmpty()) {
                        ZapiMessageNotifier.markMessageNotified(this, chatId, messageId)
                    }
                    result.success(null)
                }

                "consumeInitialChatId" -> {
                    val value = pendingChatId
                    pendingChatId = null
                    result.success(value)
                }

                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }

                "setNotificationPrefs" -> {
                    val sound = call.argument<Boolean>("sound") ?: true
                    val vibration = call.argument<Boolean>("vibration") ?: true
                    ZapiMessageNotifier.setSoundAndVibration(this, sound, vibration)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        val bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_BRIDGE_CHANNEL)
        mediaChannel = bridge
        bridge.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDocument" -> {
                    val maxBytes = (call.argument<Number>("maxBytes")?.toLong()) ?: (680L * 1024L)
                    if (pendingDocResult != null) {
                        pendingDocResult?.success(null)
                        pendingDocResult = null
                    }
                    pendingDocResult = result
                    pendingDocMaxBytes = maxBytes
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_PICK_DOCUMENT)
                    } catch (e: Exception) {
                        pendingDocResult = null
                        result.error("PICKER_ERROR", e.localizedMessage ?: "Não foi possível abrir os arquivos.", null)
                    }
                }

                "getVideoInfo" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    ioExecutor.execute {
                        try {
                            val info = ZapiVideoTranscoder.readMetadata(path)
                            mainHandler.post {
                                result.success(
                                    mapOf(
                                        "durationMs" to info.durationMs,
                                        "width" to info.width,
                                        "height" to info.height,
                                    )
                                )
                            }
                        } catch (_: Exception) {
                            mainHandler.post { result.success(null) }
                        }
                    }
                }

                "trimAndCompressVideo" -> {
                    val inputPath = call.argument<String>("inputPath") ?: ""
                    val startMs = call.argument<Number>("startMs")?.toLong() ?: 0L
                    val endMs = call.argument<Number>("endMs")?.toLong() ?: 0L
                    val maxBytes = call.argument<Number>("maxBytes")?.toLong() ?: (700L * 1024L)
                    ioExecutor.execute {
                        ZapiVideoTranscoder.trimAndCompress(
                            context = applicationContext,
                            inputPath = inputPath,
                            startMs = startMs,
                            endMs = endMs,
                            maxBytes = maxBytes,
                            onComplete = { map ->
                                mainHandler.post { result.success(map) }
                            },
                            onFailure = { msg ->
                                mainHandler.post { result.error("VIDEO_TRANSCODE_ERROR", msg, null) }
                            },
                        )
                    }
                }

                "isDeviceAuthAvailable" -> {
                    val km = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
                    result.success(km?.isDeviceSecure == true)
                }

                "authenticateWithDevice" -> {
                    val title = call.argument<String>("title") ?: "Desbloquear Zapi"
                    val subtitle = call.argument<String>("subtitle") ?: "Confirme sua biometria ou senha do celular"
                    val km = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
                    if (km == null || !km.isDeviceSecure) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    @Suppress("DEPRECATION")
                    val authIntent = km.createConfirmDeviceCredentialIntent(title, subtitle)
                    if (authIntent == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    if (pendingAuthResult != null) {
                        pendingAuthResult?.success(false)
                        pendingAuthResult = null
                    }
                    pendingAuthResult = result
                    try {
                        @Suppress("DEPRECATION")
                        startActivityForResult(authIntent, REQUEST_DEVICE_AUTH)
                    } catch (_: Exception) {
                        pendingAuthResult = null
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun inspectAndCopyDocument(uri: Uri, maxBytes: Long): Map<String, Any?> {
        var displayName = "arquivo"
        var reportedSize = -1L

        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0) {
                    val raw = cursor.getString(nameIdx)
                    if (!raw.isNullOrBlank()) displayName = raw
                }
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                    reportedSize = cursor.getLong(sizeIdx)
                }
            }
        }

        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        if (reportedSize > maxBytes) {
            return mapOf(
                "tooLarge" to true,
                "fileName" to displayName,
                "sizeBytes" to reportedSize,
                "mimeType" to mimeType,
            )
        }

        val outDir = File(cacheDir, "zapi_picked_docs").apply {
            if (!exists()) mkdirs()
        }
        val safeName = displayName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val outFile = File(outDir, "${UUID.randomUUID()}_$safeName")

        var totalRead = 0L
        val buffer = ByteArray(16 * 1024)
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(outFile).use { output ->
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    totalRead += read
                    if (totalRead > maxBytes) {
                        output.close()
                        outFile.delete()
                        return mapOf(
                            "tooLarge" to true,
                            "fileName" to displayName,
                            "sizeBytes" to totalRead,
                            "mimeType" to mimeType,
                        )
                    }
                    output.write(buffer, 0, read)
                }
            }
        } ?: throw IllegalStateException("Não foi possível abrir o arquivo selecionado.")

        return mapOf(
            "tooLarge" to false,
            "path" to outFile.absolutePath,
            "fileName" to displayName,
            "sizeBytes" to totalRead,
            "mimeType" to mimeType,
        )
    }

    private fun captureChatIntent(intent: Intent?) {
        val chatId = intent?.getStringExtra(ZapiMessageNotifier.EXTRA_CHAT_ID)
        if (!chatId.isNullOrEmpty()) {
            pendingChatId = chatId
        }
    }

    private fun startBackgroundMessageService() {
        try {
            val serviceIntent = Intent(this, ZapiMessageService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } catch (_: Exception) {
        }
    }

    private fun stopBackgroundMessageService() {
        try {
            stopService(Intent(this, ZapiMessageService::class.java))
        } catch (_: Exception) {
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }
}
