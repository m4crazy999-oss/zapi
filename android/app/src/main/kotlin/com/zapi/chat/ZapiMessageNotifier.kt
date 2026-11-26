package com.zapi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.QuerySnapshot

object ZapiMessageNotifier {
    const val CHANNEL_MESSAGES_ID = "zapi_messages_v2"
    const val CHANNEL_MESSAGES_NAME = "Mensagens"
    const val CHANNEL_MESSAGES_DESC = "Notificações de novas mensagens recebidas."

    const val CHANNEL_SERVICE_ID = "zapi_bg_service"
    const val CHANNEL_SERVICE_NAME = "Conexão em segundo plano"
    const val CHANNEL_SERVICE_DESC =
        "Mantém o recebimento de mensagens ativo com o aplicativo fechado."

    const val SERVICE_NOTIFICATION_ID = 9001
    const val SYNC_JOB_ID = 9002
    const val EXTRA_CHAT_ID = "zapi_chat_id"

    private const val PREFS_NAME = "zapi_bg_prefs"
    private const val KEY_BG_ENABLED = "bg_enabled"
    private const val KEY_IS_FOREGROUND = "is_foreground"
    private const val KEY_ACTIVE_CHAT_ID = "active_chat_id"
    private const val KEY_LAST_NOTIFIED_PREFIX = "last_notified_"

    @Volatile
    var isAppForegroundVolatile: Boolean = false

    @Volatile
    var activeChatIdVolatile: String? = null

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isBackgroundEnabled(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_BG_ENABLED, true)
    }

    fun setBackgroundEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_BG_ENABLED, enabled).apply()
    }

    fun isAppForeground(context: Context): Boolean {
        return isAppForegroundVolatile || prefs(context).getBoolean(KEY_IS_FOREGROUND, false)
    }

    fun setAppForeground(context: Context, isForeground: Boolean) {
        isAppForegroundVolatile = isForeground
        prefs(context).edit().putBoolean(KEY_IS_FOREGROUND, isForeground).apply()
    }

    fun getActiveChatId(context: Context): String? {
        return activeChatIdVolatile ?: prefs(context).getString(KEY_ACTIVE_CHAT_ID, null)
    }

    fun setActiveChatId(context: Context, chatId: String?) {
        activeChatIdVolatile = chatId
        val editor = prefs(context).edit()
        if (chatId.isNullOrEmpty()) {
            editor.remove(KEY_ACTIVE_CHAT_ID)
        } else {
            editor.putString(KEY_ACTIVE_CHAT_ID, chatId)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.cancel(chatId.hashCode())
        }
        editor.apply()
    }

    fun markMessageNotified(context: Context, chatId: String, messageId: String) {
        if (chatId.isEmpty() || messageId.isEmpty()) return
        prefs(context).edit()
            .putString(KEY_LAST_NOTIFIED_PREFIX + chatId, messageId)
            .apply()
    }

    private fun getLastNotifiedMessageId(context: Context, chatId: String): String? {
        return prefs(context).getString(KEY_LAST_NOTIFIED_PREFIX + chatId, null)
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        val msgChannel = NotificationChannel(
            CHANNEL_MESSAGES_ID,
            CHANNEL_MESSAGES_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = CHANNEL_MESSAGES_DESC
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(msgChannel)

        val bgChannel = NotificationChannel(
            CHANNEL_SERVICE_ID,
            CHANNEL_SERVICE_NAME,
            NotificationManager.IMPORTANCE_MIN
        ).apply {
            description = CHANNEL_SERVICE_DESC
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(bgChannel)
    }

    fun buildServiceNotification(context: Context): Notification {
        ensureChannels(context)

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            SERVICE_NOTIFICATION_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_SERVICE_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_MIN)
        }

        return builder
            .setSmallIcon(R.drawable.ic_stat_zapi)
            .setContentTitle("Zapi ativo")
            .setContentText("Recebendo mensagens em segundo plano")
            .setColor(0xFF00A884.toInt())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    fun handleSnapshot(
        context: Context,
        currentUid: String,
        snapshot: QuerySnapshot,
        isInitialSeed: Boolean
    ) {
        if (isInitialSeed) {
            val nowMs = System.currentTimeMillis()
            for (doc in snapshot.documents) {
                evaluateDoc(
                    context = context,
                    currentUid = currentUid,
                    doc = doc,
                    allowNotifyIfUnseen = true,
                    onlyIfFreshForFirstSeed = true,
                    nowMs = nowMs
                )
            }
            return
        }

        val nowMs = System.currentTimeMillis()
        for (change in snapshot.documentChanges) {
            if (change.type == DocumentChange.Type.REMOVED) continue
            evaluateDoc(
                context = context,
                currentUid = currentUid,
                doc = change.document,
                allowNotifyIfUnseen = true,
                onlyIfFreshForFirstSeed = false,
                nowMs = nowMs
            )
        }
    }

    fun handleFetchedDocs(
        context: Context,
        currentUid: String,
        docs: List<DocumentSnapshot>
    ) {
        val nowMs = System.currentTimeMillis()
        for (doc in docs) {
            evaluateDoc(
                context = context,
                currentUid = currentUid,
                doc = doc,
                allowNotifyIfUnseen = true,
                onlyIfFreshForFirstSeed = false,
                nowMs = nowMs
            )
        }
    }

    private fun evaluateDoc(
        context: Context,
        currentUid: String,
        doc: DocumentSnapshot,
        allowNotifyIfUnseen: Boolean,
        onlyIfFreshForFirstSeed: Boolean,
        nowMs: Long
    ) {
        if (doc.metadata.hasPendingWrites()) return

        val chatId = doc.id
        val msgId = doc.getString("lastMessageId") ?: return
        if (msgId.isEmpty()) return

        val senderId = doc.getString("lastMessageSenderId") ?: return
        val lastNotified = getLastNotifiedMessageId(context, chatId)
        if (lastNotified == msgId) return

        val unreadMap = doc.get("unreadCount") as? Map<*, *>
        val unread = (unreadMap?.get(currentUid) as? Number)?.toLong() ?: 0L

        if (senderId == currentUid || unread <= 0L) {
            markMessageNotified(context, chatId, msgId)
            return
        }

        if (onlyIfFreshForFirstSeed && lastNotified == null) {
            val ts = doc.get("lastMessageAt") as? Timestamp
            val msgTimeMs = ts?.toDate()?.time
                ?: (doc.get("lastMessageClientAt") as? Number)?.toLong()
            val isFresh = msgTimeMs != null && kotlin.math.abs(nowMs - msgTimeMs) <= 90_000L
            if (!isFresh) {
                markMessageNotified(context, chatId, msgId)
                return
            }
        }

        markMessageNotified(context, chatId, msgId)

        if (!allowNotifyIfUnseen) return

        val inForeground = isAppForeground(context)
        val activeChat = getActiveChatId(context)

        // Quando o app está aberto na tela, o listener do Flutter já exibe os avisos
        // para evitar notificações duplicadas.
        if (inForeground) return
        if (activeChat == chatId) return

        val profiles = doc.get("participantProfiles") as? Map<*, *>
        val senderProfile = profiles?.get(senderId) as? Map<*, *>
        val title = (senderProfile?.get("displayName") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: "Nova mensagem"
        val body = doc.getString("lastMessage")
            ?.takeIf { it.isNotBlank() }
            ?: "Nova mensagem"

        showMessageNotification(
            context = context,
            chatId = chatId,
            title = title,
            body = body
        )
    }

    fun showMessageNotification(
        context: Context,
        chatId: String,
        title: String,
        body: String
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        ensureChannels(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        val openChatIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            chatId.hashCode(),
            openChatIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_MESSAGES_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_HIGH)
                .setDefaults(Notification.DEFAULT_ALL)
        }

        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_zapi)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setColor(0xFF00A884.toInt())
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .build()

        manager.notify(chatId.hashCode(), notification)
    }

    fun schedulePeriodicSyncJob(context: Context) {
        if (!isBackgroundEnabled(context)) return
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            ?: return

        val existing = scheduler.allPendingJobs.any { it.id == SYNC_JOB_ID }
        if (existing) return

        val jobInfo = JobInfo.Builder(
            SYNC_JOB_ID,
            ComponentName(context, ZapiSyncJobService::class.java)
        )
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(15L * 60L * 1000L)
            .setPersisted(true)
            .build()

        try {
            scheduler.schedule(jobInfo)
        } catch (_: Exception) {
        }
    }

    fun cancelPeriodicSyncJob(context: Context) {
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            ?: return
        scheduler.cancel(SYNC_JOB_ID)
    }
}
