import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/chats/domain/chat_thread.dart';
import '../constants/app_constants.dart';
import 'chat_preferences_service.dart';

final FlutterLocalNotificationsPlugin zapiLocalNotifications =
    FlutterLocalNotificationsPlugin();

/// Coordena avisos de mensagens em primeiro plano (Flutter) e em segundo plano
/// ou com o aplicativo fechado (serviço nativo Android em Kotlin).
class NotificationService {
  NotificationService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    bool Function(String chatId)? isChatMuted,
  })  : _auth = auth,
        _firestore = firestore,
        _isChatMuted = isChatMuted {
    if (Platform.isAndroid) {
      _bgChannel.setMethodCallHandler((call) async {
        if (call.method == 'openChat') {
          final chatId = call.arguments as String?;
          if (chatId != null && chatId.isNotEmpty) {
            _handleNavigateToChat(chatId);
          }
        }
      });
    }
  }

  static const MethodChannel _bgChannel =
      MethodChannel('com.zapi.chat/background_notifications');

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final bool Function(String chatId)? _isChatMuted;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatsSub;
  final Map<String, String> _lastNotifiedMessageByChat = {};
  bool _seededInitialSnapshot = false;
  bool _pluginInitialized = false;
  bool _isAppForeground = true;
  String? _boundUid;
  String? _activeChatId;
  void Function(String chatId)? _onOpenChat;
  String? _pendingChatId;

  String? get activeChatId => _activeChatId;

  void setAppForeground(bool isForeground) {
    _isAppForeground = isForeground;
    if (Platform.isAndroid) {
      unawaited(
        _bgChannel.invokeMethod<void>('setAppForeground', {
          'isForeground': isForeground,
        }).catchError((_) {}),
      );
    }
  }

  static Future<void> initializeLocalPlugin({
    required void Function(String? payload) onSelectPayload,
  }) async {
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_zapi');
    const settings = InitializationSettings(android: androidSettings);

    await zapiLocalNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        onSelectPayload(response.payload);
      },
    );

    const channel = AndroidNotificationChannel(
      AppConstants.messagesNotificationChannelId,
      AppConstants.messagesNotificationChannelName,
      description: AppConstants.messagesNotificationChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin =
        zapiLocalNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(channel);
  }

  void attachNavigationHandler(void Function(String chatId) onOpenChat) {
    _onOpenChat = onOpenChat;
    final pending = _pendingChatId;
    if (pending != null && _auth.currentUser != null) {
      _pendingChatId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onOpenChat(pending);
      });
    }
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin =
          zapiLocalNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return (await androidPlugin?.areNotificationsEnabled()) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestPermissionIfNeeded() async {
    try {
      final androidPlugin =
          zapiLocalNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled();
      if (enabled == true) return true;
      final granted =
          (await androidPlugin?.requestNotificationsPermission()) ?? false;
      if (granted && _boundUid != null) {
        await ensureBackgroundServiceStartedIfEnabled();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBackgroundModeEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _bgChannel.invokeMethod<bool>('isBackgroundEnabled')) ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setBackgroundModeEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      if (enabled) {
        await _bgChannel.invokeMethod<bool>('startBackgroundService');
      } else {
        await _bgChannel.invokeMethod<bool>('stopBackgroundService');
      }
    } catch (_) {}
  }

  Future<bool> isBackgroundServiceRunning() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _bgChannel
              .invokeMethod<bool>('isBackgroundServiceRunning')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await _bgChannel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations')) ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _bgChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  Future<void> ensureBackgroundServiceStartedIfEnabled() async {
    if (!Platform.isAndroid) return;
    try {
      final enabled = await isBackgroundModeEnabled();
      final notifGranted = await areNotificationsEnabled();
      if (enabled && notifGranted && _auth.currentUser != null) {
        await _bgChannel.invokeMethod<bool>('startBackgroundService');
      }
    } catch (_) {}
  }

  Future<void> initializeForUser(String uid) async {
    if (_boundUid == uid && _chatsSub != null) return;

    await _chatsSub?.cancel();
    _chatsSub = null;
    _lastNotifiedMessageByChat.clear();
    _seededInitialSnapshot = false;
    _boundUid = uid;

    if (!_pluginInitialized) {
      _pluginInitialized = true;
      await initializeLocalPlugin(
        onSelectPayload: (payload) {
          if (payload != null && payload.isNotEmpty) {
            _handleNavigateToChat(payload);
          }
        },
      );
      await requestPermissionIfNeeded();

      final launchDetails =
          await zapiLocalNotifications.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _handleNavigateToChat(launchPayload);
      }

      if (Platform.isAndroid) {
        try {
          final nativeChatId =
              await _bgChannel.invokeMethod<String>('consumeInitialChatId');
          if (nativeChatId != null && nativeChatId.isNotEmpty) {
            _handleNavigateToChat(nativeChatId);
          }
        } catch (_) {}
      }
    }

    setAppForeground(_isAppForeground);
    await ensureBackgroundServiceStartedIfEnabled();

    _chatsSub = _firestore
        .collection(AppConstants.chatsCollection)
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen(
      (snapshot) {
        _handleChatsSnapshot(uid, snapshot);
      },
      onError: (_) {},
    );

    final pending = _pendingChatId;
    if (pending != null && _onOpenChat != null) {
      _pendingChatId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onOpenChat?.call(pending);
      });
    }
  }

  Future<void> _handleChatsSnapshot(
    String currentUid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!_seededInitialSnapshot) {
      _seededInitialSnapshot = true;
      final now = DateTime.now();
      for (final doc in snapshot.docs) {
        if (doc.metadata.hasPendingWrites) continue;
        final thread = ChatThread.fromFirestore(doc);
        final msgId = thread.lastMessageId;
        if (msgId == null || msgId.isEmpty) continue;

        _lastNotifiedMessageByChat[thread.chatId] = msgId;

        final isIncomingUnread = thread.lastMessageSenderId != null &&
            thread.lastMessageSenderId != currentUid &&
            thread.unreadFor(currentUid) > 0;
        final isFresh = thread.lastMessageAt != null &&
            now.difference(thread.lastMessageAt!).inSeconds.abs() <= 90;
        final isViewingThisChat =
            _isAppForeground && _activeChatId == thread.chatId;
        final isMuted = _isChatMuted?.call(thread.chatId) ?? false;

        if (isIncomingUnread && isFresh && !isViewingThisChat && !isMuted) {
          if (!_isAppForeground && await isBackgroundServiceRunning()) {
            continue;
          }
          final senderProfile = thread.profileFor(thread.lastMessageSenderId!);
          final title = senderProfile?.displayName ?? 'Nova mensagem';
          final body = thread.lastMessage.isNotEmpty
              ? thread.lastMessage
              : 'Nova mensagem';
          await _showLocalNotification(
            chatId: thread.chatId,
            messageId: msgId,
            title: title,
            body: body,
          );
        }
      }
      return;
    }

    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      if (change.doc.metadata.hasPendingWrites) continue;

      final thread = ChatThread.fromFirestore(change.doc);
      final msgId = thread.lastMessageId;
      final senderId = thread.lastMessageSenderId;

      if (msgId == null ||
          msgId.isEmpty ||
          senderId == null ||
          senderId == currentUid) {
        continue;
      }

      if (_lastNotifiedMessageByChat[thread.chatId] == msgId) {
        continue;
      }
      _lastNotifiedMessageByChat[thread.chatId] = msgId;

      if (thread.unreadFor(currentUid) <= 0) {
        continue;
      }

      if (_isChatMuted?.call(thread.chatId) ?? false) {
        continue;
      }

      // Não exibe notificação se o usuário já estiver com esta conversa aberta na tela.
      if (_isAppForeground && _activeChatId == thread.chatId) {
        continue;
      }

      // Se o app está em segundo plano e o serviço nativo está ativo, ele mesmo notifica sem duplicar.
      if (!_isAppForeground && await isBackgroundServiceRunning()) {
        continue;
      }

      final senderProfile = thread.profileFor(senderId);
      final title = senderProfile?.displayName ?? 'Nova mensagem';
      final body =
          thread.lastMessage.isNotEmpty ? thread.lastMessage : 'Nova mensagem';

      await _showLocalNotification(
        chatId: thread.chatId,
        messageId: msgId,
        title: title,
        body: body,
      );
    }
  }

  Future<void> _showLocalNotification({
    required String chatId,
    required String messageId,
    required String title,
    required String body,
  }) async {
    if (Platform.isAndroid) {
      unawaited(
        _bgChannel.invokeMethod<void>('markMessageNotified', {
          'chatId': chatId,
          'messageId': messageId,
        }).catchError((_) {}),
      );
    }

    const androidDetails = AndroidNotificationDetails(
      AppConstants.messagesNotificationChannelId,
      AppConstants.messagesNotificationChannelName,
      channelDescription: AppConstants.messagesNotificationChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_stat_zapi',
      color: Color(0xFF00A884),
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      ticker: 'Nova mensagem no Zapi',
    );

    await zapiLocalNotifications.show(
      chatId.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: chatId,
    );
  }

  Future<void> setActiveChatId(String? chatId) async {
    _activeChatId = chatId;
    if (Platform.isAndroid) {
      unawaited(
        _bgChannel.invokeMethod<void>('setActiveChatId', {
          'chatId': chatId,
        }).catchError((_) {}),
      );
    }
    if (chatId != null && chatId.isNotEmpty) {
      await zapiLocalNotifications.cancel(chatId.hashCode);
    }
  }

  Future<void> clearSession() async {
    await _chatsSub?.cancel();
    _chatsSub = null;
    _lastNotifiedMessageByChat.clear();
    _seededInitialSnapshot = false;
    _activeChatId = null;
    _boundUid = null;
    if (Platform.isAndroid) {
      unawaited(
        _bgChannel
            .invokeMethod<bool>('pauseBackgroundServiceOnLogout')
            .catchError((_) => false),
      );
    }
    await zapiLocalNotifications.cancelAll();
  }

  void _handleNavigateToChat(String chatId) {
    if (_auth.currentUser != null && _onOpenChat != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onOpenChat?.call(chatId);
      });
    } else {
      _pendingChatId = chatId;
    }
  }

  Future<void> dispose() async {
    await _chatsSub?.cancel();
    _chatsSub = null;
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    isChatMuted: (chatId) => ref.read(chatPreferencesProvider).isMuted(chatId),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
