import 'package:cloud_firestore/cloud_firestore.dart';

enum StatusPrivacyMode {
  all('all', 'Todos os contatos'),
  favorites('favorites', 'Amigos favoritos'),
  custom('custom', 'Contatos selecionados');

  const StatusPrivacyMode(this.code, this.label);

  final String code;
  final String label;

  static StatusPrivacyMode fromCode(String? raw) {
    return switch (raw) {
      'favorites' => StatusPrivacyMode.favorites,
      'custom' => StatusPrivacyMode.custom,
      _ => StatusPrivacyMode.all,
    };
  }
}

class StatusItem {
  const StatusItem({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerUsername,
    required this.type,
    required this.text,
    required this.backgroundColor,
    required this.privacyMode,
    required this.allowedUids,
    required this.createdAt,
    required this.expiresAt,
    this.ownerPhotoBase64,
    this.imageBase64,
  });

  final String id;
  final String ownerUid;
  final String ownerName;
  final String ownerUsername;
  final String? ownerPhotoBase64;
  final String type; // 'text' | 'image'
  final String text;
  final int backgroundColor;
  final String? imageBase64;
  final StatusPrivacyMode privacyMode;
  final List<String> allowedUids;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isImage => type == 'image';
  bool get isText => type == 'text';
  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  String get replyPreviewLabel {
    if (isImage) {
      final clean = text.trim();
      return clean.isEmpty ? 'Status: Foto' : 'Status: $clean';
    }
    return 'Status: ${text.trim()}';
  }

  static const List<int> textBackgroundColors = [
    0xFF00A884, // Verde Zapi
    0xFF0284C7, // Azul oceano
    0xFF7C3AED, // Roxo discreto
    0xFFDB2777, // Rosa
    0xFFD97706, // Âmbar
    0xFF0F766E, // Petróleo
    0xFF334155, // Ardósia
    0xFF1F2937, // Grafite
  ];

  factory StatusItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final created =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final expires = (data['expiresAt'] as Timestamp?)?.toDate() ??
        created.add(const Duration(hours: 24));
    final rawAllowed = data['allowedUids'];

    return StatusItem(
      id: (data['id'] as String?) ?? doc.id,
      ownerUid: (data['ownerUid'] as String?) ?? '',
      ownerName: (data['ownerName'] as String?) ?? 'Contato Zapi',
      ownerUsername: (data['ownerUsername'] as String?) ?? '',
      ownerPhotoBase64: data['ownerPhotoBase64'] as String?,
      type: (data['type'] as String?) ?? 'text',
      text: (data['text'] as String?) ?? '',
      backgroundColor:
          (data['backgroundColor'] as int?) ?? textBackgroundColors.first,
      imageBase64: data['imageBase64'] as String?,
      privacyMode: StatusPrivacyMode.fromCode(data['privacyMode'] as String?),
      allowedUids: rawAllowed is List
          ? rawAllowed.whereType<String>().toList()
          : const [],
      createdAt: created,
      expiresAt: expires,
    );
  }
}

class StatusViewRecord {
  const StatusViewRecord({
    required this.viewerUid,
    required this.viewerName,
    required this.viewedAt,
    this.viewerPhotoBase64,
  });

  final String viewerUid;
  final String viewerName;
  final String? viewerPhotoBase64;
  final DateTime viewedAt;

  factory StatusViewRecord.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return StatusViewRecord(
      viewerUid: (data['viewerUid'] as String?) ?? doc.id,
      viewerName: (data['viewerName'] as String?) ?? 'Contato Zapi',
      viewerPhotoBase64: data['viewerPhotoBase64'] as String?,
      viewedAt: (data['viewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class ContactStatusGroup {
  const ContactStatusGroup({
    required this.ownerUid,
    required this.displayName,
    required this.username,
    required this.statuses,
    required this.hasUnviewed,
    this.photoBase64,
    this.isMuted = false,
  });

  final String ownerUid;
  final String displayName;
  final String username;
  final String? photoBase64;
  final List<StatusItem> statuses;
  final bool hasUnviewed;
  final bool isMuted;

  StatusItem get latest => statuses.last;
}
