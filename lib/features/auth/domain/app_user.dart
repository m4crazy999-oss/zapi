import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.about,
    this.publicId = '',
    this.photoBase64,
    this.photoUrl,
    this.bannerBase64,
    this.bannerPreset = AppConstants.defaultBannerPreset,
    this.createdAt,
    this.lastSeen,
    this.blockedUids = const [],
    this.activeChatId,
    this.hideLastSeen = false,
    this.hideReadReceipts = false,
  });

  final String uid;
  final String displayName;
  final String username;
  final String publicId;
  final String? photoBase64;
  final String? photoUrl;
  final String? bannerBase64;
  final String bannerPreset;
  final String about;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final List<String> blockedUids;
  final String? activeChatId;
  final bool hideLastSeen;
  final bool hideReadReceipts;

  bool get hasPhoto =>
      (photoBase64 != null && photoBase64!.trim().isNotEmpty) ||
      (photoUrl != null && photoUrl!.trim().isNotEmpty);

  bool get hasBanner =>
      bannerBase64 != null && bannerBase64!.trim().isNotEmpty;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawBlocked = data['blockedUids'];
    final rawBanner = (data['bannerPreset'] as String?)?.trim();
    return AppUser(
      uid: (data['uid'] as String?) ?? doc.id,
      displayName: (data['displayName'] as String?) ?? 'Usuário Zapi',
      username: (data['username'] as String?) ?? '',
      publicId: (data['publicId'] as String?) ?? '',
      photoBase64: data['photoBase64'] as String?,
      photoUrl: data['photoUrl'] as String?,
      bannerBase64: data['bannerBase64'] as String?,
      bannerPreset: (rawBanner != null && rawBanner.isNotEmpty)
          ? rawBanner
          : AppConstants.defaultBannerPreset,
      about: (data['about'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      blockedUids: rawBlocked is List
          ? rawBlocked.whereType<String>().toList()
          : const [],
      activeChatId: data['activeChatId'] as String?,
      hideLastSeen: data['hideLastSeen'] as bool? ?? false,
      hideReadReceipts: data['hideReadReceipts'] as bool? ?? false,
    );
  }

  AppUser copyWith({
    String? uid,
    String? displayName,
    String? username,
    String? publicId,
    String? photoBase64,
    String? photoUrl,
    String? bannerBase64,
    bool clearBannerBase64 = false,
    String? bannerPreset,
    String? about,
    DateTime? createdAt,
    DateTime? lastSeen,
    List<String>? blockedUids,
    String? activeChatId,
    bool? hideLastSeen,
    bool? hideReadReceipts,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      publicId: publicId ?? this.publicId,
      photoBase64: photoBase64 ?? this.photoBase64,
      photoUrl: photoUrl ?? this.photoUrl,
      bannerBase64:
          clearBannerBase64 ? null : (bannerBase64 ?? this.bannerBase64),
      bannerPreset: bannerPreset ?? this.bannerPreset,
      about: about ?? this.about,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      blockedUids: blockedUids ?? this.blockedUids,
      activeChatId: activeChatId ?? this.activeChatId,
      hideLastSeen: hideLastSeen ?? this.hideLastSeen,
      hideReadReceipts: hideReadReceipts ?? this.hideReadReceipts,
    );
  }
}
