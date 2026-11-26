import 'package:cloud_firestore/cloud_firestore.dart';

class ZapiSticker {
  const ZapiSticker({
    required this.id,
    required this.isFavorite,
    required this.isBuiltIn,
    this.assetPath,
    this.dataBase64,
    this.mimeType,
    this.sizeBytes,
    this.createdAt,
    this.lastUsedAt,
  });

  final String id;
  final String? assetPath;
  final String? dataBase64;
  final String? mimeType;
  final int? sizeBytes;
  final bool isFavorite;
  final bool isBuiltIn;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  bool get isAsset => assetPath != null && assetPath!.startsWith('asset://');

  String get resolvedAssetPath =>
      (assetPath ?? '').replaceFirst('asset://', '');

  ZapiSticker copyWith({
    bool? isFavorite,
    DateTime? lastUsedAt,
  }) {
    return ZapiSticker(
      id: id,
      assetPath: assetPath,
      dataBase64: dataBase64,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      isBuiltIn: isBuiltIn,
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
      assetPath: data['assetPath'] as String?,
      dataBase64: data['data'] as String?,
      mimeType: data['mimeType'] as String?,
      sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
      isFavorite: (data['isFavorite'] as bool?) ?? false,
      isBuiltIn: (data['isBuiltIn'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastUsedAt: (data['lastUsedAt'] as Timestamp?)?.toDate(),
    );
  }
}
