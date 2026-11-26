import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.email,
    required this.about,
    this.photoBase64,
    this.photoUrl,
    this.createdAt,
    this.lastSeen,
    this.allowEmailSearch = false,
    this.blockedUids = const [],
    this.activeChatId,
  });

  final String uid;
  final String displayName;
  final String username;
  final String email;
  final String? photoBase64;
  final String? photoUrl;
  final String about;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final bool allowEmailSearch;
  final List<String> blockedUids;
  final String? activeChatId;

  bool get hasPhoto =>
      (photoBase64 != null && photoBase64!.trim().isNotEmpty) ||
      (photoUrl != null && photoUrl!.trim().isNotEmpty);

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawBlocked = data['blockedUids'];
    return AppUser(
      uid: (data['uid'] as String?) ?? doc.id,
      displayName: (data['displayName'] as String?) ?? 'Usuário Zapi',
      username: (data['username'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      photoBase64: data['photoBase64'] as String?,
      photoUrl: data['photoUrl'] as String?,
      about: (data['about'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      allowEmailSearch: (data['allowEmailSearch'] as bool?) ?? false,
      blockedUids: rawBlocked is List
          ? rawBlocked.whereType<String>().toList()
          : const [],
      activeChatId: data['activeChatId'] as String?,
    );
  }

  AppUser copyWith({
    String? uid,
    String? displayName,
    String? username,
    String? email,
    String? photoBase64,
    String? photoUrl,
    String? about,
    DateTime? createdAt,
    DateTime? lastSeen,
    bool? allowEmailSearch,
    List<String>? blockedUids,
    String? activeChatId,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      photoBase64: photoBase64 ?? this.photoBase64,
      photoUrl: photoUrl ?? this.photoUrl,
      about: about ?? this.about,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      allowEmailSearch: allowEmailSearch ?? this.allowEmailSearch,
      blockedUids: blockedUids ?? this.blockedUids,
      activeChatId: activeChatId ?? this.activeChatId,
    );
  }
}
