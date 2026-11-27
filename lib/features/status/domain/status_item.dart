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

class StatusStylePreset {
  const StatusStylePreset({
    required this.label,
    required this.backgroundColor,
    this.backgroundGradientEnd,
    this.defaultTextColor = 0xFFFFFFFF,
  });

  final String label;
  final int backgroundColor;
  final int? backgroundGradientEnd;
  final int defaultTextColor;
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
    this.videoBase64,
    this.durationMs,
    this.backgroundGradientEnd,
    this.textColor,
    this.fontStyle = 'sans',
    this.textAlign = 'center',
    this.fontSize = 26.0,
  });

  final String id;
  final String ownerUid;
  final String ownerName;
  final String ownerUsername;
  final String? ownerPhotoBase64;
  final String type; // 'text' | 'image' | 'video'
  final String text;
  final int backgroundColor;
  final int? backgroundGradientEnd;
  final int? textColor;
  final String fontStyle; // 'sans' | 'serif' | 'mono' | 'display'
  final String textAlign; // 'left' | 'center' | 'right'
  final double fontSize;
  final String? imageBase64;
  final String? videoBase64;
  final int? durationMs;
  final StatusPrivacyMode privacyMode;
  final List<String> allowedUids;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isText => type == 'text';
  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  String get replyPreviewLabel {
    if (isImage) {
      final clean = text.trim();
      return clean.isEmpty ? 'Status: Foto' : 'Status: $clean';
    }
    if (isVideo) {
      final clean = text.trim();
      return clean.isEmpty ? 'Status: Vídeo' : 'Status: $clean';
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

  static const List<StatusStylePreset> stylePresets = [
    StatusStylePreset(
      label: 'Esmeralda',
      backgroundColor: 0xFF00A884,
      backgroundGradientEnd: 0xFF006D5B,
    ),
    StatusStylePreset(
      label: 'Oceano',
      backgroundColor: 0xFF0284C7,
      backgroundGradientEnd: 0xFF1E3A8A,
    ),
    StatusStylePreset(
      label: 'Crepúsculo',
      backgroundColor: 0xFFF97316,
      backgroundGradientEnd: 0xFFBE185D,
    ),
    StatusStylePreset(
      label: 'Violeta',
      backgroundColor: 0xFF7C3AED,
      backgroundGradientEnd: 0xFF3B0764,
    ),
    StatusStylePreset(
      label: 'Floresta',
      backgroundColor: 0xFF0F766E,
      backgroundGradientEnd: 0xFF064E3B,
    ),
    StatusStylePreset(
      label: 'Noite',
      backgroundColor: 0xFF1F2937,
      backgroundGradientEnd: 0xFF0B141A,
    ),
    StatusStylePreset(
      label: 'Verde Zapi',
      backgroundColor: 0xFF00A884,
    ),
    StatusStylePreset(
      label: 'Ardósia',
      backgroundColor: 0xFF334155,
    ),
    StatusStylePreset(
      label: 'Claro',
      backgroundColor: 0xFFF1F5F9,
      backgroundGradientEnd: 0xFFE2E8F0,
      defaultTextColor: 0xFF0F172A,
    ),
  ];

  static const List<int> textColorOptions = [
    0xFFFFFFFF,
    0xFF0F172A,
    0xFFFEF08A,
    0xFFA7F3D0,
    0xFFBAE6FD,
    0xFFFBCFE8,
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
          (data['backgroundColor'] as num?)?.toInt() ?? textBackgroundColors.first,
      backgroundGradientEnd: (data['backgroundGradientEnd'] as num?)?.toInt(),
      textColor: (data['textColor'] as num?)?.toInt(),
      fontStyle: (data['fontStyle'] as String?) ?? 'sans',
      textAlign: (data['textAlign'] as String?) ?? 'center',
      fontSize: ((data['fontSize'] as num?)?.toDouble() ?? 26.0).clamp(14.0, 44.0),
      imageBase64: data['imageBase64'] as String?,
      videoBase64: data['videoBase64'] as String?,
      durationMs: (data['durationMs'] as num?)?.toInt(),
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
