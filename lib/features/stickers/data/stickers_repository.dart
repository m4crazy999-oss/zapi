import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/media_cache_service.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/media_processor.dart';
import '../domain/zapi_sticker.dart';

class StickersRepository {
  StickersRepository({
    required FirebaseFirestore firestore,
    required MediaCacheService mediaCache,
  })  : _firestore = firestore,
        _mediaCache = mediaCache;

  final FirebaseFirestore _firestore;
  final MediaCacheService _mediaCache;
  static const _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> _userStickersRef(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .collection(AppConstants.stickersSubcollection);
  }

  Stream<List<ZapiSticker>> watchUserStickers(String uid) {
    return _userStickersRef(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(ZapiSticker.fromFirestore)
              .where((s) => s.dataBase64 != null && s.dataBase64!.isNotEmpty)
              .toList(),
        );
  }

  Future<ZapiSticker> createCustomSticker({
    required String uid,
    required Uint8List webpBytes,
  }) async {
    if (webpBytes.length > AppConstants.maxStickerBytes) {
      throw const AppException(
        'A figurinha ficou pesada demais. Escolha uma foto mais simples.',
      );
    }

    final stickerId = 'stk_${_uuid.v4()}';
    final b64 = base64Encode(webpBytes);

    try {
      final now = DateTime.now();
      await _userStickersRef(uid).doc(stickerId).set({
        'id': stickerId,
        'data': b64,
        'mimeType': 'image/webp',
        'sizeBytes': webpBytes.length,
        'isFavorite': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUsedAt': FieldValue.serverTimestamp(),
      });

      await _mediaCache.getOrCacheSticker(
        stickerId: stickerId,
        dataBase64: b64,
        mimeType: 'image/webp',
      );

      return ZapiSticker(
        id: stickerId,
        dataBase64: b64,
        mimeType: 'image/webp',
        sizeBytes: webpBytes.length,
        isFavorite: false,
        createdAt: now,
        lastUsedAt: now,
      );
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<ZapiSticker> saveReceivedSticker({
    required String uid,
    String? chatId,
    String? mediaId,
    String? mimeType,
  }) async {
    try {
      if (chatId == null || mediaId == null || mediaId.isEmpty) {
        throw const AppException('Figurinha indisponível para salvar.');
      }

      final cachedFile = await _mediaCache.getOrFetchChatMedia(
        chatId: chatId,
        mediaId: mediaId,
        mimeType: mimeType ?? 'image/webp',
      );
      if (cachedFile == null || !await cachedFile.exists()) {
        throw const AppException('Não foi possível baixar esta figurinha.');
      }

      var webpBytes = await cachedFile.readAsBytes();
      if (webpBytes.length > AppConstants.maxStickerBytes ||
          mimeType != 'image/webp') {
        final processed = await MediaProcessor.prepareSticker(
          cachedFile.path,
          circularTransparentMask: false,
        );
        webpBytes = processed.bytes;
      }

      return createCustomSticker(uid: uid, webpBytes: webpBytes);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> toggleFavorite({
    required String uid,
    required ZapiSticker sticker,
  }) async {
    try {
      final nextFavorite = !sticker.isFavorite;
      await _userStickersRef(uid).doc(sticker.id).update({
        'isFavorite': nextFavorite,
      });
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> deleteCustomSticker({
    required String uid,
    required ZapiSticker sticker,
  }) async {
    try {
      await _userStickersRef(uid).doc(sticker.id).delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<File> _recentFile(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'zapi_recent_stickers_$uid.json'));
  }

  Future<List<String>> readRecentStickerIds(String uid) async {
    if (uid.isEmpty) return const [];
    try {
      final file = await _recentFile(uid);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> recordStickerUsed({
    required String uid,
    required ZapiSticker sticker,
  }) async {
    if (uid.isEmpty) return const [];
    try {
      final current = List<String>.from(await readRecentStickerIds(uid));
      current.remove(sticker.id);
      current.insert(0, sticker.id);
      final trimmed = current.take(24).toList();
      final file = await _recentFile(uid);
      await file.writeAsString(jsonEncode(trimmed), flush: true);
      return trimmed;
    } catch (_) {
      return const [];
    }
  }
}
