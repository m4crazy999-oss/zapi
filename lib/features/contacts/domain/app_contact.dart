import 'package:cloud_firestore/cloud_firestore.dart';

class AppContact {
  const AppContact({
    required this.contactUid,
    required this.displayName,
    required this.username,
    required this.about,
    this.nickname,
    this.photoBase64,
    this.photoUrl,
    this.isFavorite = false,
    this.addedAt,
  });

  final String contactUid;
  final String? nickname;
  final String displayName;
  final String username;
  final String? photoBase64;
  final String? photoUrl;
  final String about;
  final bool isFavorite;
  final DateTime? addedAt;

  String get effectiveName {
    final custom = nickname?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return displayName;
  }

  bool get hasNickname {
    final custom = nickname?.trim();
    return custom != null && custom.isNotEmpty;
  }

  factory AppContact.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppContact(
      contactUid: (data['contactUid'] as String?) ?? doc.id,
      nickname: data['nickname'] as String?,
      displayName: (data['displayName'] as String?) ?? 'Contato Zapi',
      username: (data['username'] as String?) ?? '',
      photoBase64: data['photoBase64'] as String?,
      photoUrl: data['photoUrl'] as String?,
      about: (data['about'] as String?) ?? '',
      isFavorite: (data['isFavorite'] as bool?) ?? false,
      addedAt: (data['addedAt'] as Timestamp?)?.toDate(),
    );
  }
}
