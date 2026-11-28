import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/media_cache_service.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/chat_id_helper.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../auth/domain/app_user.dart';
import '../domain/chat_message.dart';
import '../domain/chat_thread.dart';

class ChatsRepository {
  ChatsRepository({
    required FirebaseFirestore firestore,
    required MediaCacheService mediaCache,
    bool Function()? isConnected,
  })  : _firestore = firestore,
        _mediaCache = mediaCache,
        _isConnected = isConnected;

  final FirebaseFirestore _firestore;
  final MediaCacheService _mediaCache;
  final bool Function()? _isConnected;

  bool get _hasConnection => _isConnected?.call() ?? true;

  CollectionReference<Map<String, dynamic>> get _chatsRef =>
      _firestore.collection(AppConstants.chatsCollection);

  Stream<List<ChatThread>> watchUserChats(String uid) {
    return _chatsRef
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final threads = snapshot.docs.map(ChatThread.fromFirestore).toList();
      threads.sort((a, b) {
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return threads;
    });
  }

  Stream<ChatThread?> watchChat(String chatId) {
    return _chatsRef.doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChatThread.fromFirestore(doc);
    });
  }

  Stream<List<ChatMessage>> watchMessages({
    required String chatId,
    required int limit,
  }) {
    return _chatsRef
        .doc(chatId)
        .collection(AppConstants.messagesSubcollection)
        .orderBy('clientCreatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(ChatMessage.fromFirestore).toList();
    });
  }

  Stream<AppUser?> watchUserProfile(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Future<void> sendTextMessage({
    required String chatId,
    required AppUser sender,
    required AppUser recipient,
    required String text,
    required bool chatExists,
    ReplyQuote? replyTo,
    bool isForwarded = false,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    if (cleanText.length > AppConstants.maxMessageLength) {
      throw const AppException(
        'A mensagem ultrapassa o limite de 4.000 caracteres.',
      );
    }

    final messageRef =
        _chatsRef.doc(chatId).collection(AppConstants.messagesSubcollection).doc();
    final clientNow = DateTime.now().millisecondsSinceEpoch;

    await _commitMessage(
      chatId: chatId,
      messageId: messageRef.id,
      sender: sender,
      recipient: recipient,
      chatExists: chatExists,
      clientCreatedAt: clientNow,
      messagePayload: {
        'id': messageRef.id,
        'chatId': chatId,
        'senderId': sender.uid,
        'text': cleanText,
        'type': MessageTypes.text,
        'sizeBytes': 0,
        'clientCreatedAt': clientNow,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
        'replyTo': replyTo?.toMap(),
        'isForwarded': isForwarded,
        'reactions': <String, String>{},
        'deletedFor': <String>[],
        'deletedForEveryone': false,
      },
      preview: MessageTypes.previewLabel(
        type: MessageTypes.text,
        text: cleanText,
      ),
      lastMessageType: MessageTypes.text,
    );
  }

  Future<void> sendMediaMessage({
    required String chatId,
    required String messageId,
    required AppUser sender,
    required AppUser recipient,
    required String type,
    required int clientCreatedAt,
    String text = '',
    String? mediaId,
    String? mediaDataBase64,
    String? thumbnailBase64,
    int? width,
    int? height,
    int? durationMs,
    int? sizeBytes,
    String? mimeType,
    String? fileName,
    bool? knownChatExists,
    ReplyQuote? replyTo,
    bool isForwarded = false,
  }) async {
    final cleanCaption = text.trim();
    if (cleanCaption.length > AppConstants.maxMessageLength) {
      throw const AppException(
        'A legenda ultrapassa o limite de 4.000 caracteres.',
      );
    }

    final cleanFileName = fileName?.trim();
    final safeFileName = cleanFileName != null && cleanFileName.isNotEmpty
        ? (cleanFileName.length > 160
            ? cleanFileName.substring(0, 160)
            : cleanFileName)
        : null;

    Map<String, dynamic>? mediaPayload;
    if (mediaId != null &&
        mediaId.isNotEmpty &&
        mediaDataBase64 != null &&
        mediaDataBase64.isNotEmpty) {
      mediaPayload = {
        'id': mediaId,
        'chatId': chatId,
        'messageId': messageId,
        'senderId': sender.uid,
        'type': type,
        'mimeType': mimeType ?? 'application/octet-stream',
        if (safeFileName != null) 'fileName': safeFileName,
        'data': mediaDataBase64,
        'sizeBytes': sizeBytes ?? 0,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'createdAt': FieldValue.serverTimestamp(),
      };
    }

    await _commitMessage(
      chatId: chatId,
      messageId: messageId,
      sender: sender,
      recipient: recipient,
      chatExists: knownChatExists ?? false,
      clientCreatedAt: clientCreatedAt,
      mediaId: mediaId,
      mediaPayload: mediaPayload,
      messagePayload: {
        'id': messageId,
        'chatId': chatId,
        'senderId': sender.uid,
        'text': cleanCaption,
        'type': type,
        'mediaId': mediaId,
        'thumbnailBase64': thumbnailBase64,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes ?? 0,
        'mimeType': mimeType,
        if (safeFileName != null) 'fileName': safeFileName,
        'playedBy': <String>[],
        'reactions': <String, String>{},
        'isForwarded': isForwarded,
        'clientCreatedAt': clientCreatedAt,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
        'replyTo': replyTo?.toMap(),
        'deletedFor': <String>[],
        'deletedForEveryone': false,
      },
      preview: MessageTypes.previewLabel(
        type: type,
        text: cleanCaption,
        durationMs: durationMs,
        fileName: safeFileName,
      ),
      lastMessageType: type,
    );
  }

  Future<bool> _resolveChatExists(
    DocumentReference<Map<String, dynamic>> chatRef,
    bool hintExists,
  ) async {
    if (hintExists) return true;
    try {
      final cacheSnap =
          await chatRef.get(const GetOptions(source: Source.cache));
      if (cacheSnap.exists) return true;
    } catch (_) {}

    if (!_hasConnection) return false;

    try {
      final snap = await chatRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(milliseconds: 1200));
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  Future<AppUser> _resolveRecipientForProfile(AppUser recipient) async {
    if (recipient.username.isNotEmpty && recipient.about.isNotEmpty) {
      return recipient;
    }
    final userRef =
        _firestore.collection(AppConstants.usersCollection).doc(recipient.uid);
    try {
      final cacheSnap =
          await userRef.get(const GetOptions(source: Source.cache));
      if (cacheSnap.exists) {
        return AppUser.fromFirestore(cacheSnap);
      }
    } catch (_) {}

    if (!_hasConnection) return recipient;

    try {
      final snap = await userRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(milliseconds: 1200));
      if (snap.exists) {
        return AppUser.fromFirestore(snap);
      }
    } catch (_) {}
    return recipient;
  }

  Future<void> _commitMessage({
    required String chatId,
    required String messageId,
    required AppUser sender,
    required AppUser recipient,
    required bool chatExists,
    required int clientCreatedAt,
    required Map<String, dynamic> messagePayload,
    required String preview,
    required String lastMessageType,
    String? mediaId,
    Map<String, dynamic>? mediaPayload,
  }) async {
    final chatRef = _chatsRef.doc(chatId);
    final messageRef =
        chatRef.collection(AppConstants.messagesSubcollection).doc(messageId);

    final actualChatExists = await _resolveChatExists(chatRef, chatExists);
    final resolvedRecipient = actualChatExists
        ? recipient
        : await _resolveRecipientForProfile(recipient);

    final senderProfile = ChatParticipantProfile(
      uid: sender.uid,
      displayName: sender.displayName,
      username: sender.username,
      about: sender.about,
      bannerPreset: sender.bannerPreset,
      photoBase64: sender.photoBase64,
      photoUrl: sender.photoUrl,
    ).toMap();

    final recipientProfile = ChatParticipantProfile(
      uid: resolvedRecipient.uid,
      displayName: resolvedRecipient.displayName,
      username: resolvedRecipient.username,
      about: resolvedRecipient.about,
      bannerPreset: resolvedRecipient.bannerPreset,
      photoBase64: resolvedRecipient.photoBase64,
      photoUrl: resolvedRecipient.photoUrl,
    ).toMap();

    WriteBatch buildBatch(bool exists) {
      final batch = _firestore.batch();

      if (mediaId != null && mediaPayload != null) {
        final mediaRef =
            chatRef.collection(AppConstants.mediaSubcollection).doc(mediaId);
        batch.set(mediaRef, mediaPayload);
      }

      batch.set(messageRef, messagePayload);

      if (!exists) {
        final participants =
            ChatIdHelper.sortedParticipants(sender.uid, resolvedRecipient.uid);
        batch.set(chatRef, {
          'participants': participants,
          'participantProfiles': {
            sender.uid: senderProfile,
            resolvedRecipient.uid: recipientProfile,
          },
          'blockedBy': {
            sender.uid: false,
            resolvedRecipient.uid: false,
          },
          'lastMessage': preview,
          'lastMessageType': lastMessageType,
          'lastMessageId': messageId,
          'lastMessageSenderId': sender.uid,
          'lastMessageStatus': 'sent',
          'lastMessageClientAt': clientCreatedAt,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'unreadCount': {
            sender.uid: 0,
            resolvedRecipient.uid: 1,
          },
          'typing': {
            sender.uid: null,
            resolvedRecipient.uid: null,
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final updates = <String, dynamic>{
          'participantProfiles.${sender.uid}': senderProfile,
          'lastMessage': preview,
          'lastMessageType': lastMessageType,
          'lastMessageId': messageId,
          'lastMessageSenderId': sender.uid,
          'lastMessageStatus': 'sent',
          'lastMessageClientAt': clientCreatedAt,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'unreadCount.${resolvedRecipient.uid}': FieldValue.increment(1),
          'typing.${sender.uid}': null,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (resolvedRecipient.username.isNotEmpty) {
          updates['participantProfiles.${resolvedRecipient.uid}'] =
              recipientProfile;
        }
        batch.update(chatRef, updates);
      }
      return batch;
    }

    Future<void> recoverIfRace(FirebaseException error) async {
      if (error.code == 'not-found' ||
          error.code == 'already-exists' ||
          error.code == 'permission-denied') {
        final serverSnap = await chatRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        if (serverSnap.exists != actualChatExists) {
          await buildBatch(serverSnap.exists)
              .commit()
              .timeout(const Duration(seconds: 3));
        }
      }
    }

    try {
      final commitFuture = buildBatch(actualChatExists).commit();
      if (!_hasConnection) {
        // Sem conexão agora: gravação já entrou na fila local e sincroniza ao reconectar.
        unawaited(
          commitFuture.catchError((Object error) async {
            if (error is FirebaseException) {
              try {
                await recoverIfRace(error);
              } catch (_) {}
            }
          }),
        );
        return;
      }

      try {
        await commitFuture.timeout(const Duration(milliseconds: 1200));
      } on TimeoutException {
        // Rede lenta: gravação já está na fila local; mantém sincronizando sem travar a UI.
        unawaited(
          commitFuture.catchError((Object error) async {
            if (error is FirebaseException) {
              try {
                await recoverIfRace(error);
              } catch (_) {}
            }
          }),
        );
      }
    } on FirebaseException catch (error) {
      try {
        await recoverIfRace(error);
        return;
      } catch (_) {}
      throw FirebaseErrorMapper.map(error);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> setUserBlocked({
    required String currentUid,
    required String peerUid,
    required String chatId,
    required bool blocked,
  }) async {
    if (currentUid.isEmpty || peerUid.isEmpty) return;
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(currentUid)
          .update({
        'blockedUids': blocked
            ? FieldValue.arrayUnion([peerUid])
            : FieldValue.arrayRemove([peerUid]),
      }).timeout(const Duration(seconds: 6));

      try {
        await _chatsRef.doc(chatId).update({
          'blockedBy.$currentUid': blocked,
        }).timeout(const Duration(seconds: 4));
      } catch (_) {
        // A conversa pode ainda não existir no servidor.
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    if (!_hasConnection) return;
    try {
      await _chatsRef.doc(chatId).update({
        'typing.$uid': isTyping ? FieldValue.serverTimestamp() : null,
      }).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Conversa ainda não criada ou dispositivo offline.
    }
  }

  Future<void> markAudioPlayed({
    required String chatId,
    required String messageId,
    required String currentUid,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || currentUid.isEmpty) return;
    try {
      await _chatsRef
          .doc(chatId)
          .collection(AppConstants.messagesSubcollection)
          .doc(messageId)
          .update({
        'playedBy': FieldValue.arrayUnion([currentUid]),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> markMessagesDelivered({
    required String chatId,
    required String currentUid,
    required List<ChatMessage> messages,
    ChatThread? thread,
  }) async {
    final toDeliver = messages
        .where(
          (m) =>
              m.senderId != currentUid &&
              !m.hasPendingWrites &&
              !m.isUploading &&
              m.status == MessageStatus.sent,
        )
        .toList();

    if (toDeliver.isEmpty &&
        !(thread != null &&
            thread.lastMessageSenderId != currentUid &&
            thread.lastMessageStatus == 'sent')) {
      return;
    }

    try {
      final batch = _firestore.batch();
      final messagesCol =
          _chatsRef.doc(chatId).collection(AppConstants.messagesSubcollection);

      for (final msg in toDeliver) {
        batch.update(messagesCol.doc(msg.id), {
          'status': 'delivered',
          'deliveredAt': FieldValue.serverTimestamp(),
        });
      }

      if (thread != null &&
          thread.lastMessageSenderId != currentUid &&
          thread.lastMessageStatus == 'sent') {
        batch.update(_chatsRef.doc(chatId), {
          'lastMessageStatus': 'delivered',
        });
      }

      await batch.commit();
    } catch (_) {}
  }

  Future<void> markIncomingChatsDelivered({
    required String currentUid,
    required List<ChatThread> chats,
  }) async {
    final pendingDelivery = chats.where(
      (chat) =>
          !chat.hasPendingWrites &&
          chat.lastMessageSenderId != null &&
          chat.lastMessageSenderId != currentUid &&
          chat.lastMessageStatus == 'sent',
    );

    for (final chat in pendingDelivery) {
      try {
        final msgSnap = await _chatsRef
            .doc(chat.chatId)
            .collection(AppConstants.messagesSubcollection)
            .where('status', isEqualTo: 'sent')
            .limit(20)
            .get();

        final incomingDocs = msgSnap.docs
            .where((d) => d.data()['senderId'] != currentUid)
            .toList();

        final batch = _firestore.batch();
        for (final doc in incomingDocs) {
          batch.update(doc.reference, {
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          });
        }
        batch.update(_chatsRef.doc(chat.chatId), {
          'lastMessageStatus': 'delivered',
        });
        await batch.commit();
      } catch (_) {}
    }
  }

  Future<void> markChatAsRead({
    required String chatId,
    required String currentUid,
    required List<ChatMessage> messages,
    ChatThread? thread,
    bool sendReadReceipt = true,
  }) async {
    if (!sendReadReceipt) {
      final toDeliver = messages
          .where(
            (m) =>
                m.senderId != currentUid &&
                !m.hasPendingWrites &&
                !m.isUploading &&
                m.status == MessageStatus.sent,
          )
          .toList();

      final needsUnreadReset = thread != null &&
          (thread.unreadFor(currentUid) > 0 ||
              (thread.lastMessageSenderId != currentUid &&
                  thread.lastMessageStatus == 'sent'));

      if (toDeliver.isEmpty && !needsUnreadReset) return;

      try {
        final batch = _firestore.batch();
        final messagesCol =
            _chatsRef.doc(chatId).collection(AppConstants.messagesSubcollection);

        for (final msg in toDeliver) {
          batch.update(messagesCol.doc(msg.id), {
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          });
        }

        if (thread != null) {
          final updates = <String, dynamic>{
            'unreadCount.$currentUid': 0,
          };
          if (thread.lastMessageSenderId != currentUid &&
              thread.lastMessageStatus == 'sent') {
            updates['lastMessageStatus'] = 'delivered';
          }
          batch.update(_chatsRef.doc(chatId), updates);
        }

        await batch.commit();
      } catch (_) {}
      return;
    }

    final toRead = messages
        .where(
          (m) =>
              m.senderId != currentUid &&
              !m.hasPendingWrites &&
              !m.isUploading &&
              m.status != MessageStatus.read,
        )
        .toList();

    final needsThreadUpdate = thread != null &&
        (thread.unreadFor(currentUid) > 0 ||
            (thread.lastMessageSenderId != currentUid &&
                thread.lastMessageStatus != 'read'));

    if (toRead.isEmpty && !needsThreadUpdate) return;

    try {
      final batch = _firestore.batch();
      final messagesCol =
          _chatsRef.doc(chatId).collection(AppConstants.messagesSubcollection);

      for (final msg in toRead) {
        batch.update(messagesCol.doc(msg.id), {
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      if (thread != null) {
        final updates = <String, dynamic>{
          'unreadCount.$currentUid': 0,
        };
        if (thread.lastMessageSenderId != currentUid &&
            thread.lastMessageStatus != 'read') {
          updates['lastMessageStatus'] = 'read';
        }
        batch.update(_chatsRef.doc(chatId), updates);
      }

      await batch.commit();
    } catch (_) {}
  }

  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String uid,
    required String emoji,
    required String? currentReaction,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || uid.isEmpty) return;
    final cleanEmoji = emoji.trim();
    if (cleanEmoji.isEmpty) return;
    final remove = currentReaction == cleanEmoji;

    try {
      await _chatsRef
          .doc(chatId)
          .collection(AppConstants.messagesSubcollection)
          .doc(messageId)
          .update({
        'reactions.$uid': remove ? FieldValue.delete() : cleanEmoji,
      }).timeout(const Duration(seconds: 6));
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
    required String uid,
  }) async {
    try {
      await _chatsRef
          .doc(chatId)
          .collection(AppConstants.messagesSubcollection)
          .doc(messageId)
          .update({
        'deletedFor': FieldValue.arrayUnion([uid]),
      }).timeout(const Duration(seconds: 6));
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> deleteMessageForEveryone({
    required String chatId,
    required String messageId,
    required bool isLastMessage,
    String? mediaId,
  }) async {
    try {
      final chatRef = _chatsRef.doc(chatId);
      final msgRef =
          chatRef.collection(AppConstants.messagesSubcollection).doc(messageId);

      final batch = _firestore.batch();
      batch.update(msgRef, {
        'deletedForEveryone': true,
        'text': '',
        'mediaId': null,
        'thumbnailBase64': null,
        'mediaUrl': null,
        'thumbnailUrl': null,
        'fileName': null,
        'reactions': <String, String>{},
        'deletedAt': FieldValue.serverTimestamp(),
      });
      if (mediaId != null && mediaId.isNotEmpty) {
        batch.delete(
          chatRef.collection(AppConstants.mediaSubcollection).doc(mediaId),
        );
      }
      if (isLastMessage) {
        batch.update(chatRef, {
          'lastMessage': 'Mensagem apagada',
          'lastMessageType': MessageTypes.text,
        });
      }
      await batch.commit().timeout(const Duration(seconds: 6));

      if (mediaId != null && mediaId.isNotEmpty) {
        unawaited(
          _mediaCache.removeCachedChatMedia(chatId: chatId, mediaId: mediaId),
        );
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
