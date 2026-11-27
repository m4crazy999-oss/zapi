import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_formatter.dart';

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

class MessageTypes {
  MessageTypes._();

  static const String text = 'text';
  static const String image = 'image';
  static const String audio = 'audio';
  static const String sticker = 'sticker';
  static const String file = 'file';
  static const String video = 'video';

  static String previewLabel({
    required String type,
    required String text,
    int? durationMs,
    String? fileName,
  }) {
    final clean = text.trim();
    switch (type) {
      case MessageTypes.image:
        if (clean.isNotEmpty) {
          final short = clean.length > 80 ? '${clean.substring(0, 77)}...' : clean;
          return 'Foto: $short';
        }
        return 'Foto';
      case MessageTypes.video:
        if (clean.isNotEmpty) {
          final short = clean.length > 80 ? '${clean.substring(0, 77)}...' : clean;
          return 'Vídeo: $short';
        }
        if (durationMs != null && durationMs > 0) {
          return 'Vídeo ${DateFormatter.formatDuration(Duration(milliseconds: durationMs))}';
        }
        return 'Vídeo';
      case MessageTypes.audio:
        final dur = durationMs != null && durationMs > 0
            ? DateFormatter.formatDuration(Duration(milliseconds: durationMs))
            : '0:00';
        return 'Áudio $dur';
      case MessageTypes.file:
        final cleanFile = (fileName ?? '').trim();
        if (cleanFile.isNotEmpty) {
          final short = cleanFile.length > 80
              ? '${cleanFile.substring(0, 77)}...'
              : cleanFile;
          return 'Arquivo: $short';
        }
        return 'Arquivo';
      case MessageTypes.sticker:
        return 'Figurinha';
      case MessageTypes.text:
      default:
        return clean.length > 120 ? '${clean.substring(0, 117)}...' : clean;
    }
  }
}

class ReplyQuote {
  const ReplyQuote({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
  });

  final String messageId;
  final String senderId;
  final String senderName;
  final String text;

  factory ReplyQuote.fromMap(Map<String, dynamic> map) {
    return ReplyQuote(
      messageId: (map['messageId'] as String?) ?? '',
      senderId: (map['senderId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.clientCreatedAt,
    required this.status,
    required this.hasPendingWrites,
    required this.deletedFor,
    required this.deletedForEveryone,
    this.createdAt,
    this.replyTo,
    this.mediaId,
    this.thumbnailBase64,
    this.mediaUrl,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.mimeType,
    this.fileName,
    this.playedBy = const [],
    this.reactions = const {},
    this.isForwarded = false,
    this.localMediaPath,
    this.localThumbnailPath,
    this.isUploading = false,
    this.uploadProgress,
    this.uploadFailed = false,
    this.uploadError,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String type;
  final DateTime clientCreatedAt;
  final DateTime? createdAt;
  final MessageStatus status;
  final bool hasPendingWrites;
  final ReplyQuote? replyTo;
  final List<String> deletedFor;
  final bool deletedForEveryone;

  // Campos de mídia em Firestore Spark (chats/{chatId}/media/{mediaId})
  final String? mediaId;
  final String? thumbnailBase64;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final String? mimeType;
  final String? fileName;
  final List<String> playedBy;
  final Map<String, String> reactions;
  final bool isForwarded;

  // Campos locais transitórios para envio otimista com progresso e retry
  final String? localMediaPath;
  final String? localThumbnailPath;
  final bool isUploading;
  final double? uploadProgress;
  final bool uploadFailed;
  final String? uploadError;

  DateTime get effectiveTime => createdAt ?? clientCreatedAt;

  MessageStatus get effectiveStatus {
    if (uploadFailed) return MessageStatus.failed;
    if (isUploading || hasPendingWrites) return MessageStatus.sending;
    return status;
  }

  bool get isImage => type == MessageTypes.image;
  bool get isAudio => type == MessageTypes.audio;
  bool get isSticker => type == MessageTypes.sticker;
  bool get isFile => type == MessageTypes.file;
  bool get isVideo => type == MessageTypes.video;
  bool get isText => type == MessageTypes.text;

  bool isHiddenFor(String uid) => deletedFor.contains(uid);

  bool wasPlayedBy(String uid) => uid.isNotEmpty && playedBy.contains(uid);

  String? reactionFor(String uid) => uid.isEmpty ? null : reactions[uid];

  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      if (emoji.trim().isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  String get quotePreviewText => MessageTypes.previewLabel(
        type: type,
        text: text,
        durationMs: durationMs,
        fileName: fileName,
      );

  static MessageStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'read':
        return MessageStatus.read;
      case 'delivered':
        return MessageStatus.delivered;
      case 'failed':
        return MessageStatus.failed;
      case 'sent':
      default:
        return MessageStatus.sent;
    }
  }

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};

    final rawClientMillis = data['clientCreatedAt'];
    final clientTime = rawClientMillis is int
        ? DateTime.fromMillisecondsSinceEpoch(rawClientMillis)
        : DateTime.now();

    final rawReply = data['replyTo'];
    final replyQuote = rawReply is Map
        ? ReplyQuote.fromMap(Map<String, dynamic>.from(rawReply))
        : null;

    final rawDeletedFor = data['deletedFor'];
    final deletedFor = rawDeletedFor is List
        ? rawDeletedFor.whereType<String>().toList()
        : const <String>[];

    final rawPlayedBy = data['playedBy'];
    final playedBy = rawPlayedBy is List
        ? rawPlayedBy.whereType<String>().toList()
        : const <String>[];

    final rawReactions = data['reactions'];
    final reactions = <String, String>{};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        if (key is String &&
            value is String &&
            key.isNotEmpty &&
            value.trim().isNotEmpty) {
          reactions[key] = value;
        }
      });
    }

    return ChatMessage(
      id: (data['id'] as String?) ?? doc.id,
      chatId: (data['chatId'] as String?) ?? '',
      senderId: (data['senderId'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      type: (data['type'] as String?) ?? MessageTypes.text,
      clientCreatedAt: clientTime,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      status: _parseStatus(data['status'] as String?),
      hasPendingWrites: doc.metadata.hasPendingWrites,
      replyTo: replyQuote,
      deletedFor: deletedFor,
      deletedForEveryone: (data['deletedForEveryone'] as bool?) ?? false,
      mediaId: data['mediaId'] as String?,
      thumbnailBase64: data['thumbnailBase64'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      width: (data['width'] as num?)?.toInt(),
      height: (data['height'] as num?)?.toInt(),
      durationMs: (data['durationMs'] as num?)?.toInt(),
      sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
      mimeType: data['mimeType'] as String?,
      fileName: data['fileName'] as String?,
      playedBy: playedBy,
      reactions: reactions,
      isForwarded: (data['isForwarded'] as bool?) ?? false,
    );
  }
}
