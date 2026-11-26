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
  })  : _firestore = firestore,
        _mediaCache = mediaCache;

  final FirebaseFirestore _firestore;
  final MediaCacheService _mediaCache;

  CollectionReference<Map<String, dynamic>> get _chatsRef =>
      _firestore.collection(AppConstants.chatsCollection);

  Stream<List<ChatThread>> watchUserChats(String uid) {
    return _chatsRef
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return snapshot.docs.map(ChatThread.fromFirestore).toList();
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
        .snapshots(includeMetadataChanges: true)
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
        'deletedFor': <String>[],
        'deletedForEveryone': false,
      },
      preview: MessageTypes.previewLabel(
        type: MessageTypes.text,
        text: cleanText,
      ),
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
    String? assetPath,
    int? width,
    int? height,
    int? durationMs,
    int? sizeBytes,
    String? mimeType,
    bool? knownChatExists,
    ReplyQuote? replyTo,
  }) async {
    final cleanCaption = text.trim();
    if (cleanCaption.length > AppConstants.maxMessageLength) {
      throw const AppException(
        'A legenda ultrapassa o limite de 4.000 caracteres.',
      );
    }

    var chatExists = knownChatExists ?? false;
    if (!chatExists) {
      try {
        final chatSnap = await _chatsRef.doc(chatId).get();
        chatExists = chatSnap.exists;
      } catch (_) {}
    }

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
      chatExists: chatExists,
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
        'assetPath': assetPath,
        'width': width,
        'height': height,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes ?? 0,
        'mimeType': mimeType,
        'playedBy': <String>[],
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
      ),
    );
  }

  Future<void> _commitMessage({
    required String chatId,
    required String messageId,
    required AppUser sender,
    required AppUser recipient,
    required bool chatExists,
    required Map<String, dynamic> messagePayload,
    required String preview,
    String? mediaId,
    Map<String, dynamic>? mediaPayload,
  }) async {
    final chatRef = _chatsRef.doc(chatId);
    final messageRef =
        chatRef.collection(AppConstants.messagesSubcollection).doc(messageId);

    final senderProfile = ChatParticipantProfile(
      uid: sender.uid,
      displayName: sender.displayName,
      username: sender.username,
      photoBase64: sender.photoBase64,
      photoUrl: sender.photoUrl,
    ).toMap();

    final recipientProfile = ChatParticipantProfile(
      uid: recipient.uid,
      displayName: recipient.displayName,
      username: recipient.username,
      photoBase64: recipient.photoBase64,
      photoUrl: recipient.photoUrl,
    ).toMap();

    final batch = _firestore.batch();

    if (mediaId != null && mediaPayload != null) {
      final mediaRef =
          chatRef.collection(AppConstants.mediaSubcollection).doc(mediaId);
      batch.set(mediaRef, mediaPayload);
    }

    batch.set(messageRef, messagePayload);

    if (!chatExists) {
      final participants =
          ChatIdHelper.sortedParticipants(sender.uid, recipient.uid);
      batch.set(chatRef, {
        'participants': participants,
        'participantProfiles': {
          sender.uid: senderProfile,
          recipient.uid: recipientProfile,
        },
        'blockedBy': {
          sender.uid: false,
          recipient.uid: false,
        },
        'lastMessage': preview,
        'lastMessageId': messageId,
        'lastMessageSenderId': sender.uid,
        'lastMessageStatus': 'sent',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount': {
          sender.uid: 0,
          recipient.uid: 1,
        },
        'typing': {
          sender.uid: null,
          recipient.uid: null,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(chatRef, {
        'participantProfiles.${sender.uid}': senderProfile,
        'participantProfiles.${recipient.uid}': recipientProfile,
        'lastMessage': preview,
        'lastMessageId': messageId,
        'lastMessageSenderId': sender.uid,
        'lastMessageStatus': 'sent',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadCount.${recipient.uid}': FieldValue.increment(1),
        'typing.${sender.uid}': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    try {
      await Future.any<void>([
        batch.commit(),
        Future<void>.delayed(const Duration(milliseconds: 450)),
      ]);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    try {
      await _chatsRef.doc(chatId).update({
        'typing.$uid': isTyping ? FieldValue.serverTimestamp() : null,
      });
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
      });
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
  }) async {
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
      });
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
        'assetPath': null,
        'mediaUrl': null,
        'thumbnailUrl': null,
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
        });
      }
      await batch.commit();

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
