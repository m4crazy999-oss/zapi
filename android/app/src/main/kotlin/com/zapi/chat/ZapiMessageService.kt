package com.zapi.chat

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

class ZapiMessageService : Service() {

    companion object {
        @Volatile
        var isRunning: Boolean = false
            private set

        const val ACTION_STOP = "com.zapi.chat.ACTION_STOP_BG_SERVICE"
    }

    private var listenerRegistration: ListenerRegistration? = null
    private var boundUid: String? = null
    private var initialSeedDone: Boolean = false

    override fun onCreate() {
        super.onCreate()
        if (FirebaseApp.getApps(this).isEmpty()) {
            FirebaseApp.initializeApp(this)
        }
        ZapiMessageNotifier.ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()

        if (intent?.action == ACTION_STOP || !ZapiMessageNotifier.isBackgroundEnabled(this)) {
            stopCleanly()
            return START_NOT_STICKY
        }

        val currentUser = try {
            FirebaseAuth.getInstance().currentUser
        } catch (_: Exception) {
            null
        }

        if (currentUser == null) {
            stopCleanly()
            return START_NOT_STICKY
        }

        isRunning = true
        bindFirestoreListener(currentUser.uid)
        return START_STICKY
    }

    private fun startForegroundCompat() {
        val notification = ZapiMessageNotifier.buildServiceNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                ZapiMessageNotifier.SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
            startForeground(ZapiMessageNotifier.SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun stopCleanly() {
        listenerRegistration?.remove()
        listenerRegistration = null
        boundUid = null
        isRunning = false
        stopForegroundCompat()
        stopSelf()
    }

    private fun bindFirestoreListener(uid: String) {
        if (boundUid == uid && listenerRegistration != null) return

        listenerRegistration?.remove()
        listenerRegistration = null
        boundUid = uid
        initialSeedDone = false

        listenerRegistration = FirebaseFirestore.getInstance()
            .collection("chats")
            .whereArrayContains("participants", uid)
            .addSnapshotListener { snapshot, error ->
                if (error != null || snapshot == null) return@addSnapshotListener
                val isInitial = !initialSeedDone
                initialSeedDone = true
                ZapiMessageNotifier.handleSnapshot(
                    context = applicationContext,
                    currentUid = uid,
                    snapshot = snapshot,
                    isInitialSeed = isInitial
                )
            }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        ZapiMessageNotifier.setAppForeground(applicationContext, false)
        ZapiMessageNotifier.setActiveChatId(applicationContext, null)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        listenerRegistration?.remove()
        listenerRegistration = null
        boundUid = null
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
