import 'package:cloud_firestore/cloud_firestore.dart';

class ChatParticipantProfile {
  const ChatParticipantProfile({
    required this.uid,
    required this.displayName,
    required this.username,
    this.about,
    this.bannerPreset,
    this.photoBase64,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String username;
  final String? about;
  final String? bannerPreset;
  final String? photoBase64;
  final String? photoUrl;

  factory ChatParticipantProfile.fromMap(
    String uid,
    Map<String, dynamic> map,
  ) {
    return ChatParticipantProfile(
      uid: uid,
      displayName: (map['displayName'] as String?) ?? 'Usuário Zapi',
      username: (map['username'] as String?) ?? '',
      about: map['about'] as String?,
      bannerPreset: map['bannerPreset'] as String?,
      photoBase64: map['photoBase64'] as String?,
      photoUrl: map['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'username': username,
      'about': about,
      'bannerPreset': bannerPreset,
      'photoBase64': photoBase64,
      'photoUrl': photoUrl,
    };
  }
}

class ChatThread {
  const ChatThread({
    required this.chatId,
    required this.participants,
    required this.participantProfiles,
    required this.lastMessage,
    required this.lastMessageStatus,
    required this.unreadCount,
    required this.typingAt,
    required this.blockedBy,
    this.lastMessageId,
    this.lastMessageType,
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.hasPendingWrites = false,
  });

  final String chatId;
  final List<String> participants;
  final Map<String, ChatParticipantProfile> participantProfiles;
  final String lastMessage;
  final String? lastMessageId;
  final String? lastMessageType;
  final String? lastMessageSenderId;
  final String lastMessageStatus;
  final DateTime? lastMessageAt;
  final Map<String, int> unreadCount;
  final Map<String, DateTime> typingAt;
  final Map<String, bool> blockedBy;
  final bool hasPendingWrites;

  String otherParticipantUid(String currentUid) {
    for (final uid in participants) {
      if (uid != currentUid) return uid;
    }
    final parts = chatId.split('_');
    if (parts.length == 2) {
      return parts[0] == currentUid ? parts[1] : parts[0];
    }
    return '';
  }

  ChatParticipantProfile? profileFor(String uid) => participantProfiles[uid];

  int unreadFor(String uid) => unreadCount[uid] ?? 0;

  bool isTyping(String uid) {
    final ts = typingAt[uid];
    if (ts == null) return false;
    return DateTime.now().difference(ts).inSeconds.abs() <= 6;
  }

  bool isBlockedBy(String uid) => blockedBy[uid] == true;

  factory ChatThread.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    final rawParticipants = data['participants'];
    final participants = rawParticipants is List
        ? rawParticipants.whereType<String>().toList()
        : <String>[];

    final profiles = <String, ChatParticipantProfile>{};
    final rawProfiles = data['participantProfiles'];
    if (rawProfiles is Map) {
      rawProfiles.forEach((key, value) {
        if (key is String && value is Map) {
          profiles[key] = ChatParticipantProfile.fromMap(
            key,
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final unreadMap = <String, int>{};
    final rawUnread = data['unreadCount'];
    if (rawUnread is Map) {
      rawUnread.forEach((key, value) {
        if (key is String && value is num) {
          unreadMap[key] = value.toInt();
        }
      });
    }

    final typingMap = <String, DateTime>{};
    final rawTyping = data['typing'];
    if (rawTyping is Map) {
      rawTyping.forEach((key, value) {
        if (key is String && value is Timestamp) {
          typingMap[key] = value.toDate();
        }
      });
    }

    final blockedMap = <String, bool>{};
    final rawBlocked = data['blockedBy'];
    if (rawBlocked is Map) {
      rawBlocked.forEach((key, value) {
        if (key is String && value is bool) {
          blockedMap[key] = value;
        }
      });
    }

    final rawClientAt = data['lastMessageClientAt'];
    final clientDate = rawClientAt is int
        ? DateTime.fromMillisecondsSinceEpoch(rawClientAt)
        : null;

    return ChatThread(
      chatId: doc.id,
      participants: participants,
      participantProfiles: profiles,
      lastMessage: (data['lastMessage'] as String?) ?? '',
      lastMessageId: data['lastMessageId'] as String?,
      lastMessageType: data['lastMessageType'] as String?,
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      lastMessageStatus: (data['lastMessageStatus'] as String?) ?? 'sent',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ??
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          clientDate,
      unreadCount: unreadMap,
      typingAt: typingMap,
      blockedBy: blockedMap,
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }
}
