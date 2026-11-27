import 'package:cloud_firestore/cloud_firestore.dart';

class ZapiSticker {
  const ZapiSticker({
    required this.id,
    required this.isFavorite,
    this.dataBase64,
    this.mimeType,
    this.sizeBytes,
    this.createdAt,
    this.lastUsedAt,
  });

  final String id;
  final String? dataBase64;
  final String? mimeType;
  final int? sizeBytes;
  final bool isFavorite;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  ZapiSticker copyWith({
    bool? isFavorite,
    DateTime? lastUsedAt,
  }) {
    return ZapiSticker(
      id: id,
      dataBase64: dataBase64,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  factory ZapiSticker.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ZapiSticker(
      id: (data['id'] as String?) ?? doc.id,
      dataBase64: data['data'] as String?,
      mimeType: data['mimeType'] as String?,
      sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
      isFavorite: (data['isFavorite'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
    );
  }
}
