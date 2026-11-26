package com.zapi.chat

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.zapi.chat/background_notifications"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingChatId: String? = null

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
        super.onDestroy()
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

                else -> result.notImplemented()
            }
        }
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
