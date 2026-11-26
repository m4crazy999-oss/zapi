import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/chats/domain/chat_thread.dart';
import '../constants/app_constants.dart';

final FlutterLocalNotificationsPlugin zapiLocalNotifications =
    FlutterLocalNotificationsPlugin();

/// Serviço de notificações locais via listener em tempo real do Firestore
/// (compatível com o plano gratuito Spark, sem Cloud Functions ou FCM pago).
/// Limitação: funciona enquanto o app estiver aberto ou em segundo plano com o
/// processo ativo; se o usuário ou o sistema encerrar o app completamente, não
/// há push remoto em segundo plano sem Cloud Functions.
class NotificationService {
  NotificationService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
  }

  static Future<void> initializeLocalPlugin({
    required void Function(String? payload) onSelectPayload,
  }) async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
      onOpenChat(pending);
    }
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
      await _requestPermissions();

      final launchDetails =
          await zapiLocalNotifications.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _handleNavigateToChat(launchPayload);
      }
    }

    _chatsSub = _firestore
        .collection(AppConstants.chatsCollection)
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      _handleChatsSnapshot(uid, snapshot);
    });

    final pending = _pendingChatId;
    if (pending != null && _onOpenChat != null) {
      _pendingChatId = null;
      _onOpenChat!(pending);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      final androidPlugin =
          zapiLocalNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> _handleChatsSnapshot(
    String currentUid,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!_seededInitialSnapshot) {
      _seededInitialSnapshot = true;
      for (final doc in snapshot.docs) {
        final thread = ChatThread.fromFirestore(doc);
        if (thread.lastMessageId != null) {
          _lastNotifiedMessageByChat[thread.chatId] = thread.lastMessageId!;
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

      // Não exibe notificação se o usuário já estiver com esta conversa aberta na tela.
      if (_isAppForeground && _activeChatId == thread.chatId) {
        continue;
      }

      final senderProfile = thread.profileFor(senderId);
      final title = senderProfile?.displayName ?? 'Nova mensagem';
      final body =
          thread.lastMessage.isNotEmpty ? thread.lastMessage : 'Nova mensagem';

      await _showLocalNotification(
        chatId: thread.chatId,
        title: title,
        body: body,
      );
    }
  }

  Future<void> _showLocalNotification({
    required String chatId,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      AppConstants.messagesNotificationChannelId,
      AppConstants.messagesNotificationChannelName,
      channelDescription: AppConstants.messagesNotificationChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
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
    await zapiLocalNotifications.cancelAll();
  }

  void _handleNavigateToChat(String chatId) {
    if (_auth.currentUser != null && _onOpenChat != null) {
      _onOpenChat!(chatId);
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
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
