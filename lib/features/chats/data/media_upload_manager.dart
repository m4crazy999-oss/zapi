import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/media_cache_service.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/media_processor.dart';
import '../../auth/domain/app_user.dart';
import '../../stickers/domain/zapi_sticker.dart';
import '../domain/chat_message.dart';
import '../presentation/providers/chats_providers.dart';

class PendingMediaItem {
  const PendingMediaItem({
    required this.id,
    required this.chatId,
    required this.type,
    required this.sender,
    required this.recipient,
    required this.text,
    required this.clientCreatedAt,
    required this.localMediaPath,
    this.localThumbnailPath,
    this.thumbnailBase64,
    this.width,
    this.height,
    this.durationMs,
    this.sizeBytes,
    this.mimeType,
    this.replyTo,
    this.progress = 0.0,
    this.isFailed = false,
    this.isCanceled = false,
    this.errorMessage,
  });

  final String id;
  final String chatId;
  final String type;
  final AppUser sender;
  final AppUser recipient;
  final String text;
  final int clientCreatedAt;
  final String localMediaPath;
  final String? localThumbnailPath;
  final String? thumbnailBase64;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? sizeBytes;
  final String? mimeType;
  final ReplyQuote? replyTo;
  final double progress;
  final bool isFailed;
  final bool isCanceled;
  final String? errorMessage;

  PendingMediaItem copyWith({
    String? localMediaPath,
    String? localThumbnailPath,
    String? thumbnailBase64,
    int? width,
    int? height,
    int? sizeBytes,
    double? progress,
    bool? isFailed,
    bool? isCanceled,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PendingMediaItem(
      id: id,
      chatId: chatId,
      type: type,
      sender: sender,
      recipient: recipient,
      text: text,
      clientCreatedAt: clientCreatedAt,
      localMediaPath: localMediaPath ?? this.localMediaPath,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      progress: progress ?? this.progress,
      isFailed: isFailed ?? this.isFailed,
      isCanceled: isCanceled ?? this.isCanceled,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  ChatMessage toOptimisticMessage() {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: sender.uid,
      text: text,
      type: type,
      clientCreatedAt: DateTime.fromMillisecondsSinceEpoch(clientCreatedAt),
      status: isFailed ? MessageStatus.failed : MessageStatus.sending,
      hasPendingWrites: !isFailed,
      replyTo: replyTo,
      deletedFor: const [],
      deletedForEveryone: false,
      mediaId: id,
      thumbnailBase64: thumbnailBase64,
      width: width,
      height: height,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      localMediaPath: localMediaPath,
      localThumbnailPath: localThumbnailPath,
      isUploading: !isFailed,
      uploadProgress: progress,
      uploadFailed: isFailed,
      uploadError: errorMessage,
    );
  }
}

class MediaUploadManager
    extends Notifier<Map<String, List<PendingMediaItem>>> {
  static const _uuid = Uuid();

  @override
  Map<String, List<PendingMediaItem>> build() {
    return const {};
  }

  List<PendingMediaItem> pendingForChat(String chatId) {
    return state[chatId] ?? const [];
  }

  Future<void> enqueuePhotos({
    required String chatId,
    required AppUser sender,
    required AppUser recipient,
    required List<({String sourcePath, String caption})> photos,
    ReplyQuote? replyTo,
  }) async {
    var baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    for (final photo in photos) {
      final messageId = _uuid.v4();
      final item = PendingMediaItem(
        id: messageId,
        chatId: chatId,
        type: MessageTypes.image,
        sender: sender,
        recipient: recipient,
        text: photo.caption.trim(),
        clientCreatedAt: baseTimestamp++,
        localMediaPath: photo.sourcePath,
        localThumbnailPath: photo.sourcePath,
        mimeType: 'image/jpeg',
        replyTo: replyTo,
      );
      _upsertItem(item);
      unawaited(_processAndUploadPhoto(item));
    }
  }

  Future<void> enqueueAudio({
    required String chatId,
    required AppUser sender,
    required AppUser recipient,
    required String filePath,
    required int durationMs,
    ReplyQuote? replyTo,
  }) async {
    final file = File(filePath);
    final sizeBytes = await file.exists() ? await file.length() : 0;
    if (sizeBytes <= 0) return;

    if (sizeBytes > AppConstants.maxChatAudioBytes ||
        sizeBytes * 4 > AppConstants.maxFirestoreMediaBase64Chars * 3) {
      throw const AppException(
        'O áudio ficou longo demais, grave um menor.',
      );
    }

    final messageId = _uuid.v4();
    final item = PendingMediaItem(
      id: messageId,
      chatId: chatId,
      type: MessageTypes.audio,
      sender: sender,
      recipient: recipient,
      text: '',
      clientCreatedAt: DateTime.now().millisecondsSinceEpoch,
      localMediaPath: filePath,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      mimeType: 'audio/mp4',
      replyTo: replyTo,
    );
    _upsertItem(item);
    unawaited(_uploadAudio(item));
  }

  Future<void> sendSticker({
    required String chatId,
    required AppUser sender,
    required AppUser recipient,
    required ZapiSticker sticker,
    required bool chatExists,
    ReplyQuote? replyTo,
  }) async {
    final messageId = _uuid.v4();
    final repo = ref.read(chatsRepositoryProvider);

    if (sticker.isAsset && sticker.assetPath != null) {
      await repo.sendMediaMessage(
        chatId: chatId,
        messageId: messageId,
        sender: sender,
        recipient: recipient,
        type: MessageTypes.sticker,
        assetPath: sticker.assetPath,
        width: AppConstants.stickerSizePx,
        height: AppConstants.stickerSizePx,
        mimeType: 'image/png',
        sizeBytes: 0,
        clientCreatedAt: DateTime.now().millisecondsSinceEpoch,
        knownChatExists: chatExists,
        replyTo: replyTo,
      );
      return;
    }

    final rawBase64 = sticker.dataBase64?.trim() ?? '';
    if (rawBase64.isEmpty) {
      throw const AppException('Figurinha indisponível para envio.');
    }

    final bytes = base64Decode(rawBase64);
    if (bytes.length > AppConstants.maxStickerBytes) {
      throw const AppException(
        'Não foi possível enviar esta figurinha. Escolha outra.',
      );
    }

    final mimeType = sticker.mimeType ?? 'image/webp';
    await ref.read(mediaCacheServiceProvider).seedChatMediaBytes(
          chatId: chatId,
          mediaId: messageId,
          mimeType: mimeType,
          bytes: bytes,
        );

    await repo.sendMediaMessage(
      chatId: chatId,
      messageId: messageId,
      sender: sender,
      recipient: recipient,
      type: MessageTypes.sticker,
      mediaId: messageId,
      mediaDataBase64: rawBase64,
      width: AppConstants.stickerSizePx,
      height: AppConstants.stickerSizePx,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      clientCreatedAt: DateTime.now().millisecondsSinceEpoch,
      knownChatExists: chatExists,
      replyTo: replyTo,
    );
  }

  Future<void> retryUpload(String chatId, String messageId) async {
    final item = _findItem(chatId, messageId);
    if (item == null) return;

    final reset = item.copyWith(
      progress: 0.0,
      isFailed: false,
      isCanceled: false,
      clearError: true,
    );
    _upsertItem(reset);

    if (reset.type == MessageTypes.image) {
      await _processAndUploadPhoto(reset);
    } else if (reset.type == MessageTypes.audio) {
      await _uploadAudio(reset);
    }
  }

  Future<void> cancelUpload(String chatId, String messageId) async {
    final existing = _findItem(chatId, messageId);
    if (existing != null) {
      _upsertItem(existing.copyWith(isCanceled: true));
    }
    _removeItem(chatId, messageId);
    unawaited(
      ref
          .read(mediaCacheServiceProvider)
          .removeCachedChatMedia(chatId: chatId, mediaId: messageId),
    );
  }

  Future<void> _processAndUploadPhoto(PendingMediaItem initial) async {
    var current = initial;
    try {
      current = current.copyWith(progress: 0.15);
      _upsertItem(current);

      final processed =
          await MediaProcessor.prepareChatPhoto(current.localMediaPath);
      if (_isCanceled(current.chatId, current.id)) return;

      final mainBase64 = base64Encode(processed.imageBytes);
      final thumbBase64 = base64Encode(processed.thumbnailBytes);

      if (processed.sizeBytes > AppConstants.maxChatImageBytes ||
          mainBase64.length > AppConstants.maxFirestoreMediaBase64Chars) {
        throw const AppException(
          'A foto é muito grande, tente escolher outra.',
        );
      }

      // Salva no cache em disco para o remetente não precisar ler do Firestore depois.
      final cachedFile =
          await ref.read(mediaCacheServiceProvider).seedChatMediaBytes(
                chatId: current.chatId,
                mediaId: current.id,
                mimeType: 'image/jpeg',
                bytes: processed.imageBytes,
              );

      current = current.copyWith(
        localMediaPath: cachedFile.path,
        localThumbnailPath: processed.thumbnailPath,
        thumbnailBase64: thumbBase64,
        width: processed.width,
        height: processed.height,
        sizeBytes: processed.sizeBytes,
        progress: 0.72,
      );
      _upsertItem(current);

      if (_isCanceled(current.chatId, current.id)) return;

      await ref.read(chatsRepositoryProvider).sendMediaMessage(
            chatId: current.chatId,
            messageId: current.id,
            sender: current.sender,
            recipient: current.recipient,
            type: MessageTypes.image,
            text: current.text,
            mediaId: current.id,
            mediaDataBase64: mainBase64,
            thumbnailBase64: thumbBase64,
            width: current.width,
            height: current.height,
            sizeBytes: current.sizeBytes,
            mimeType: 'image/jpeg',
            clientCreatedAt: current.clientCreatedAt,
            replyTo: current.replyTo,
          );

      _removeItem(current.chatId, current.id);
    } catch (error) {
      if (_isCanceled(current.chatId, current.id)) return;
      final mapped = FirebaseErrorMapper.map(error);
      final latest = _findItem(current.chatId, current.id) ?? current;
      _upsertItem(
        latest.copyWith(
          isFailed: true,
          errorMessage: mapped.message,
        ),
      );
    }
  }

  Future<void> _uploadAudio(PendingMediaItem initial) async {
    var current = initial;
    try {
      current = current.copyWith(progress: 0.25);
      _upsertItem(current);

      final audioFile = File(current.localMediaPath);
      if (!await audioFile.exists()) {
        throw const AppException('Arquivo de áudio local não encontrado.');
      }

      final bytes = await audioFile.readAsBytes();
      final audioBase64 = base64Encode(bytes);

      if (bytes.length > AppConstants.maxChatAudioBytes ||
          audioBase64.length > AppConstants.maxFirestoreMediaBase64Chars) {
        throw const AppException(
          'O áudio ficou longo demais, grave um menor.',
        );
      }

      if (_isCanceled(current.chatId, current.id)) return;

      final cachedFile =
          await ref.read(mediaCacheServiceProvider).seedChatMediaBytes(
                chatId: current.chatId,
                mediaId: current.id,
                mimeType: 'audio/mp4',
                bytes: bytes,
              );

      current = current.copyWith(
        localMediaPath: cachedFile.path,
        sizeBytes: bytes.length,
        progress: 0.72,
      );
      _upsertItem(current);

      await ref.read(chatsRepositoryProvider).sendMediaMessage(
            chatId: current.chatId,
            messageId: current.id,
            sender: current.sender,
            recipient: current.recipient,
            type: MessageTypes.audio,
            mediaId: current.id,
            mediaDataBase64: audioBase64,
            durationMs: current.durationMs,
            sizeBytes: bytes.length,
            mimeType: 'audio/mp4',
            clientCreatedAt: current.clientCreatedAt,
            replyTo: current.replyTo,
          );

      _removeItem(current.chatId, current.id);
    } catch (error) {
      if (_isCanceled(current.chatId, current.id)) return;
      final mapped = FirebaseErrorMapper.map(error);
      final latest = _findItem(current.chatId, current.id) ?? current;
      _upsertItem(
        latest.copyWith(
          isFailed: true,
          errorMessage: mapped.message,
        ),
      );
    }
  }

  PendingMediaItem? _findItem(String chatId, String id) {
    final list = state[chatId];
    if (list == null) return null;
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool _isCanceled(String chatId, String id) {
    final item = _findItem(chatId, id);
    return item == null || item.isCanceled;
  }

  void _upsertItem(PendingMediaItem item) {
    if (!ref.mounted) return;
    final currentList = List<PendingMediaItem>.from(state[item.chatId] ?? []);
    final idx = currentList.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      currentList[idx] = item;
    } else {
      currentList.insert(0, item);
    }
    state = {
      ...state,
      item.chatId: currentList,
    };
  }

  void _removeItem(String chatId, String id) {
    if (!ref.mounted) return;
    final currentList = List<PendingMediaItem>.from(state[chatId] ?? []);
    currentList.removeWhere((e) => e.id == id);
    final nextMap = Map<String, List<PendingMediaItem>>.from(state);
    if (currentList.isEmpty) {
      nextMap.remove(chatId);
    } else {
      nextMap[chatId] = currentList;
    }
    state = nextMap;
  }
}

final mediaUploadManagerProvider =
    NotifierProvider<MediaUploadManager, Map<String, List<PendingMediaItem>>>(
  MediaUploadManager.new,
);
