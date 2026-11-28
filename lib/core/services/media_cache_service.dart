import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../constants/app_constants.dart';
import '../utils/app_exceptions.dart';

class MediaCacheService {
  MediaCacheService({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;
  final Map<String, Future<File?>> _inFlight = {};

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'zapi_media_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _extensionForMime(String? mimeType, {String? fileName}) {
    if (fileName != null && fileName.trim().isNotEmpty) {
      final rawExt = p.extension(fileName.trim()).replaceFirst('.', '');
      if (RegExp(r'^[a-zA-Z0-9]{1,8}$').hasMatch(rawExt)) {
        return rawExt.toLowerCase();
      }
    }
    switch (mimeType) {
      case 'video/mp4':
        return 'mp4';
      case 'audio/mp4':
      case 'audio/aac':
        return 'm4a';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/ogg':
        return 'ogg';
      case 'application/pdf':
        return 'pdf';
      case 'text/plain':
        return 'txt';
      case 'application/zip':
        return 'zip';
      case 'image/webp':
        return 'webp';
      case 'image/png':
        return 'png';
      case 'image/jpeg':
        return 'jpg';
      default:
        return 'bin';
    }
  }

  String _safeKey(String raw) => raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  Future<File> _chatMediaTargetFile({
    required String chatId,
    required String mediaId,
    String? mimeType,
    String? fileName,
  }) async {
    final root = await _rootDir();
    final chatDir = Directory(p.join(root.path, 'chats', _safeKey(chatId)));
    if (!await chatDir.exists()) {
      await chatDir.create(recursive: true);
    }
    final ext = _extensionForMime(mimeType, fileName: fileName);
    return File(p.join(chatDir.path, '${_safeKey(mediaId)}.$ext'));
  }

  /// Verifica síncronamente apenas quando o caminho já foi resolvido antes,
  /// ou busca no cache em disco primeiro e lê o Firestore somente uma vez.
  Future<File?> getOrFetchChatMedia({
    required String chatId,
    required String mediaId,
    String? mimeType,
    String? fileName,
  }) {
    if (chatId.isEmpty || mediaId.isEmpty) return Future.value(null);
    final key = '$chatId::$mediaId::${mimeType ?? ''}::${fileName ?? ''}';
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _resolveChatMedia(
      chatId: chatId,
      mediaId: mediaId,
      mimeType: mimeType,
      fileName: fileName,
    ).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<File?> getCachedChatMediaIfExists({
    required String chatId,
    required String mediaId,
    String? mimeType,
    String? fileName,
  }) async {
    if (chatId.isEmpty || mediaId.isEmpty) return null;
    try {
      final target = await _chatMediaTargetFile(
        chatId: chatId,
        mediaId: mediaId,
        mimeType: mimeType,
        fileName: fileName,
      );
      if (await target.exists() && await target.length() > 0) {
        return target;
      }
    } catch (_) {}
    return null;
  }

  Future<File?> _resolveChatMedia({
    required String chatId,
    required String mediaId,
    String? mimeType,
    String? fileName,
  }) async {
    final target = await _chatMediaTargetFile(
      chatId: chatId,
      mediaId: mediaId,
      mimeType: mimeType,
      fileName: fileName,
    );
    if (await target.exists() && await target.length() > 0) {
      return target;
    }

    final doc = await _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.mediaSubcollection)
        .doc(mediaId)
        .get()
        .timeout(const Duration(seconds: 12));

    if (!doc.exists) return null;
    final dataMap = doc.data();
    final b64 = dataMap?['data'] as String?;
    if (b64 == null || b64.isEmpty) return null;

    final resolvedMime = (dataMap?['mimeType'] as String?) ?? mimeType;
    final resolvedName = (dataMap?['fileName'] as String?) ?? fileName;
    final resolvedTarget = await _chatMediaTargetFile(
      chatId: chatId,
      mediaId: mediaId,
      mimeType: resolvedMime,
      fileName: resolvedName,
    );

    final bytes = base64Decode(b64);
    if (bytes.isEmpty) {
      throw const AppException('Arquivo de mídia inválido.');
    }

    await _writeAtomically(resolvedTarget, bytes);
    return resolvedTarget;
  }

  /// Grava imediatamente no cache local ao enviar mídia para evitar nova leitura no Firestore.
  Future<File> seedChatMediaBytes({
    required String chatId,
    required String mediaId,
    required String mimeType,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final target = await _chatMediaTargetFile(
      chatId: chatId,
      mediaId: mediaId,
      mimeType: mimeType,
      fileName: fileName,
    );
    await _writeAtomically(target, bytes);
    return target;
  }

  Future<void> removeCachedChatMedia({
    required String chatId,
    required String mediaId,
  }) async {
    try {
      final root = await _rootDir();
      final chatDir = Directory(p.join(root.path, 'chats', _safeKey(chatId)));
      if (!await chatDir.exists()) return;
      final prefix = _safeKey(mediaId);
      await for (final entity in chatDir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('$prefix.')) {
          await entity.delete().catchError((_) => entity);
        }
      }
    } catch (_) {}
  }

  Future<File?> getOrCacheSticker({
    required String stickerId,
    required String dataBase64,
    String mimeType = 'image/webp',
  }) async {
    if (stickerId.isEmpty || dataBase64.isEmpty) return null;
    final root = await _rootDir();
    final stickerDir = Directory(p.join(root.path, 'stickers'));
    if (!await stickerDir.exists()) {
      await stickerDir.create(recursive: true);
    }
    final ext = _extensionForMime(mimeType);
    final file = File(p.join(stickerDir.path, '${_safeKey(stickerId)}.$ext'));
    if (await file.exists() && await file.length() > 0) {
      return file;
    }
    final bytes = base64Decode(dataBase64);
    await _writeAtomically(file, bytes);
    return file;
  }

  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final tempFile = File('${target.path}.tmp');
    await tempFile.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.delete().catchError((_) => target);
    }
    await tempFile.rename(target.path);
  }

  Future<int> computeCacheSizeBytes() async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) return 0;
      var total = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length().catchError((_) => 0);
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAllCache() async {
    try {
      final root = await _rootDir();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (_) {}
  }
}

final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) {
  return MediaCacheService(
    firestore: ref.watch(firebaseFirestoreProvider),
  );
});
