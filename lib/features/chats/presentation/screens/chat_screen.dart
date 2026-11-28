import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/services/native_media_bridge.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/chat_wallpaper.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_camera_screen.dart';
import '../../../../core/widgets/zapi_photo_editor_screen.dart';
import '../../../../core/widgets/zapi_video_trimmer_screen.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../stickers/domain/zapi_sticker.dart';
import '../../../stickers/presentation/providers/stickers_providers.dart';
import '../../../stickers/presentation/widgets/sticker_tray.dart';
import '../../data/chats_repository.dart';
import '../../data/media_upload_manager.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_thread.dart';
import '../providers/chats_providers.dart';
import '../widgets/chat_audio_mini_bar.dart';
import '../widgets/chat_forward_sheet.dart';
import '../widgets/chat_message_actions_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/reply_preview_bar.dart';
import '../widgets/voice_recorder_bar.dart';
import 'fullscreen_image_viewer.dart';
import 'fullscreen_video_viewer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.initialReply,
  });

  final String chatId;
  final ReplyQuote? initialReply;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  int _messageLimit = AppConstants.messagesPageSize;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isAtBottom = true;
  bool _hasNewBelow = false;
  bool _isSending = false;
  bool _isCurrentlyTyping = false;
  bool _hasTextInput = false;
  bool _showStickerTray = false;
  bool _isSearching = false;
  bool _draftLoaded = false;
  String _searchQuery = '';
  int _searchMatchIndex = 0;
  int _lastVisibleCount = 0;
  String? _lastMarkedReadMsgId;

  Timer? _typingTimer;
  Timer? _draftTimer;
  ReplyQuote? _replyingTo;
  final Set<String> _pendingHideMessageIds = {};
  final Map<String, Timer> _pendingHideTimers = {};
  final Map<String, GlobalKey> _messageKeys = {};
  late final NotificationService _notificationService;
  late final ChatsRepository _chatsRepository;
  late final ChatPreferencesNotifier _prefsNotifier;
  late final AudioPlaybackController _audioController;
  late final VoiceRecorderController _voiceController;

  String get _myUid => ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  String get _peerUid {
    final parts = widget.chatId.split('_');
    if (parts.length == 2) {
      return parts[0] == _myUid ? parts[1] : parts[0];
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationService = ref.read(notificationServiceProvider);
    _chatsRepository = ref.read(chatsRepositoryProvider);
    _prefsNotifier = ref.read(chatPreferencesProvider.notifier);
    _audioController = ref.read(audioPlaybackProvider.notifier);
    _notificationService.setActiveChatId(widget.chatId);
    _scrollController.addListener(_onScroll);

    _applyInitialDraft(ref.read(chatPreferencesProvider));

    _replyingTo = widget.initialReply;
    _voiceController = VoiceRecorderController(
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      onFeedbackMessage: (msg) {
        if (!mounted) return;
        ZapiToast.showError(context, msg, bottomOffset: 80);
      },
      onBeforeRecordStart: () => _audioController.deactivateForRecording(),
      onCompleted: _handleRecordedVoice,
    );
  }

  void _applyInitialDraft(ChatPreferencesState prefs) {
    if (_draftLoaded || !prefs.isLoaded) return;
    _draftLoaded = true;
    final savedDraft = prefs.draftFor(widget.chatId);
    if (savedDraft.isNotEmpty && _textController.text.isEmpty) {
      _textController.text = savedDraft;
      _textController.selection =
          TextSelection.collapsed(offset: savedDraft.length);
      _hasTextInput = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _draftTimer?.cancel();
    unawaited(_prefsNotifier.setChatDraft(widget.chatId, _textController.text));
    for (final entry in _pendingHideTimers.entries) {
      entry.value.cancel();
      if (_myUid.isNotEmpty) {
        unawaited(
          _chatsRepository.deleteMessageForMe(
            chatId: widget.chatId,
            messageId: entry.key,
            uid: _myUid,
          ),
        );
      }
    }
    _pendingHideTimers.clear();
    if (_isCurrentlyTyping && _myUid.isNotEmpty) {
      _chatsRepository.setTyping(
        chatId: widget.chatId,
        uid: _myUid,
        isTyping: false,
      );
    }
    _notificationService.setActiveChatId(null);
    unawaited(_audioController.pause());
    unawaited(_voiceController.dispose());
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _hideMessageOptimistically(String messageId) {
    if (_myUid.isEmpty) return;
    _pendingHideTimers[messageId]?.cancel();
    setState(() {
      _pendingHideMessageIds.add(messageId);
    });

    final timer = Timer(const Duration(seconds: 3), () async {
      _pendingHideTimers.remove(messageId);
      try {
        await _chatsRepository.deleteMessageForMe(
          chatId: widget.chatId,
          messageId: messageId,
          uid: _myUid,
        );
      } on AppException catch (e) {
        if (!mounted) return;
        setState(() => _pendingHideMessageIds.remove(messageId));
        ZapiToast.showError(context, e.message, bottomOffset: 80);
      }
    });
    _pendingHideTimers[messageId] = timer;

    ZapiToast.showUndo(
      context,
      message: 'Mensagem apagada para você',
      bottomOffset: 80,
      onUndo: () {
        _pendingHideTimers.remove(messageId)?.cancel();
        if (mounted) {
          setState(() => _pendingHideMessageIds.remove(messageId));
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notificationService.setActiveChatId(widget.chatId);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _notificationService.setActiveChatId(null);
      _stopTypingNow();
      unawaited(_audioController.pause());
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final nearBottom = position.pixels <= 100;
    if (nearBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = nearBottom;
        if (nearBottom) {
          _hasNewBelow = false;
        }
      });
    }

    if (position.pixels >= position.maxScrollExtent - 180 &&
        !_isLoadingMore &&
        _hasMore) {
      setState(() {
        _isLoadingMore = true;
        _messageLimit += AppConstants.messagesPageSize;
      });
    }
  }

  void _onTextChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    if (hasText != _hasTextInput) {
      setState(() => _hasTextInput = hasText);
    }

    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_prefsNotifier.setChatDraft(widget.chatId, value));
    });

    if (!hasText) {
      _stopTypingNow();
      return;
    }

    if (!_isCurrentlyTyping && _myUid.isNotEmpty) {
      _isCurrentlyTyping = true;
      ref.read(chatsRepositoryProvider).setTyping(
            chatId: widget.chatId,
            uid: _myUid,
            isTyping: true,
          );
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), _stopTypingNow);
  }

  void _stopTypingNow() {
    _typingTimer?.cancel();
    if (_isCurrentlyTyping && _myUid.isNotEmpty) {
      _isCurrentlyTyping = false;
      ref.read(chatsRepositoryProvider).setTyping(
            chatId: widget.chatId,
            uid: _myUid,
            isTyping: false,
          );
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    if (_hasNewBelow) {
      setState(() => _hasNewBelow = false);
    }
  }

  AppUser _resolveEffectivePeer(AppUser? peerUser, ChatThread? thread) {
    return peerUser ??
        _fallbackPeerUser(
          peerUid: _peerUid,
          thread: thread,
        );
  }

  AppUser? _resolveCurrentUser(AppUser? loadedProfile) {
    if (loadedProfile != null) return loadedProfile;
    final authUser = ref.read(firebaseAuthProvider).currentUser;
    if (authUser == null) return null;
    final fallbackName = (authUser.displayName ?? '').trim().isNotEmpty
        ? authUser.displayName!.trim()
        : 'Usuário Zapi';
    return AppUser(
      uid: authUser.uid,
      displayName: fallbackName,
      username: '',
      about: AppConstants.defaultAbout,
    );
  }

  void _insertEmoji(String emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start =
        selection.isValid ? selection.start.clamp(0, text.length) : text.length;
    final end =
        selection.isValid ? selection.end.clamp(0, text.length) : text.length;
    final nextText = text.replaceRange(start, end, emoji);
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _onTextChanged(nextText);
  }

  Future<void> _sendMessage({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    final text = _textController.text.trim();
    final effectiveSender = _resolveCurrentUser(currentUser);
    if (text.isEmpty || _isSending || effectiveSender == null) return;

    final effectivePeer = _resolveEffectivePeer(peerUser, thread);
    final quote = _replyingTo;
    _draftTimer?.cancel();
    _textController.clear();
    unawaited(_prefsNotifier.setChatDraft(widget.chatId, ''));
    _stopTypingNow();
    setState(() {
      _hasTextInput = false;
      _replyingTo = null;
      _isSending = true;
    });

    unawaited(HapticFeedback.lightImpact());
    try {
      await ref.read(chatsRepositoryProvider).sendTextMessage(
            chatId: widget.chatId,
            sender: effectiveSender,
            recipient: effectivePeer,
            text: text,
            chatExists: thread != null,
            replyTo: quote,
          );
      _scrollToBottom();
    } on AppException catch (e) {
      if (!mounted) return;
      _textController.text = text;
      unawaited(_prefsNotifier.setChatDraft(widget.chatId, text));
      setState(() => _hasTextInput = true);
      ZapiToast.showError(context, e.message, bottomOffset: 80);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _openCameraAndMedia({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    final effectiveSender = _resolveCurrentUser(currentUser);
    if (effectiveSender == null) return;
    _focusNode.unfocus();

    final captured = await Navigator.push<ZapiCapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => const ZapiCameraScreen(
          allowVideo: true,
          maxPhotos: 10,
        ),
      ),
    );
    if (captured == null || captured.paths.isEmpty || !mounted) return;

    final effectivePeer = _resolveEffectivePeer(peerUser, thread);

    if (captured.kind == ZapiCapturedMediaKind.photos) {
      final edited = await Navigator.push<
          List<({String sourcePath, String caption})>>(
        context,
        MaterialPageRoute(
          builder: (_) => ZapiPhotoEditorScreen(
            initialPaths: captured.paths,
            recipientName: effectivePeer.displayName,
          ),
        ),
      );
      if (edited == null || edited.isEmpty || !mounted) return;

      final quote = _replyingTo;
      setState(() {
        _replyingTo = null;
        _showStickerTray = false;
      });

      await ref.read(mediaUploadManagerProvider.notifier).enqueuePhotos(
            chatId: widget.chatId,
            sender: effectiveSender,
            recipient: effectivePeer,
            photos: edited,
            replyTo: quote,
          );
      _scrollToBottom();
      return;
    }

    if (captured.kind == ZapiCapturedMediaKind.video) {
      final trimmed = await Navigator.push<TrimmedVideoOutput>(
        context,
        MaterialPageRoute(
          builder: (_) => ZapiVideoTrimmerScreen(
            videoPath: captured.paths.first,
            maxBytes: AppConstants.maxChatVideoBytes,
            maxDurationMs: 60000,
            primaryButtonLabel: 'Enviar vídeo',
          ),
        ),
      );
      if (trimmed == null || !mounted) return;

      final quote = _replyingTo;
      setState(() {
        _replyingTo = null;
        _showStickerTray = false;
      });

      try {
        await ref.read(mediaUploadManagerProvider.notifier).enqueueVideo(
              chatId: widget.chatId,
              sender: effectiveSender,
              recipient: effectivePeer,
              filePath: trimmed.path,
              durationMs: trimmed.durationMs,
              sizeBytes: trimmed.sizeBytes,
              caption: trimmed.caption,
              replyTo: quote,
            );
        _scrollToBottom();
      } on AppException catch (e) {
        if (!mounted) return;
        ZapiToast.showError(context, e.message, bottomOffset: 80);
      }
    }
  }

  Future<void> _pickAndSendFile({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    final effectiveSender = _resolveCurrentUser(currentUser);
    if (effectiveSender == null) return;
    _focusNode.unfocus();

    try {
      final picked = await NativeMediaBridge.pickDocument(
        maxBytes: AppConstants.maxChatFileBytes,
      );
      if (picked == null || !mounted) return;

      final effectivePeer = _resolveEffectivePeer(peerUser, thread);
      final quote = _replyingTo;
      setState(() {
        _replyingTo = null;
        _showStickerTray = false;
      });

      await ref.read(mediaUploadManagerProvider.notifier).enqueueFile(
            chatId: widget.chatId,
            sender: effectiveSender,
            recipient: effectivePeer,
            filePath: picked.path,
            fileName: picked.fileName,
            mimeType: picked.mimeType,
            sizeBytes: picked.sizeBytes,
            replyTo: quote,
          );
      _scrollToBottom();
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message, bottomOffset: 80);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível enviar este arquivo.',
        bottomOffset: 80,
      );
    }
  }

  Future<void> _handleRecordedVoice(String filePath, int durationMs) async {
    final currentUser =
        _resolveCurrentUser(ref.read(currentUserProfileProvider).value);
    if (currentUser == null) return;
    final thread = ref.read(chatThreadProvider(widget.chatId)).value;
    final peerUser = ref.read(peerUserProfileProvider(_peerUid)).value;
    final effectivePeer = _resolveEffectivePeer(peerUser, thread);
    final quote = _replyingTo;

    if (mounted && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }

    try {
      await ref.read(mediaUploadManagerProvider.notifier).enqueueAudio(
            chatId: widget.chatId,
            sender: currentUser,
            recipient: effectivePeer,
            filePath: filePath,
            durationMs: durationMs,
            replyTo: quote,
          );
      _scrollToBottom();
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message, bottomOffset: 80);
    }
  }

  AppUser _fallbackPeerUser({
    required String peerUid,
    required ChatThread? thread,
  }) {
    final contact = ref.read(contactsByUidProvider)[peerUid];
    final profile = thread?.profileFor(peerUid);
    return AppUser(
      uid: peerUid,
      displayName: contact?.displayName ?? profile?.displayName ?? 'Usuário Zapi',
      username: contact?.username ?? profile?.username ?? '',
      about: contact?.about ?? profile?.about ?? '',
      bannerPreset: profile?.bannerPreset ?? AppConstants.defaultBannerPreset,
      photoBase64: contact?.photoBase64 ?? profile?.photoBase64,
      photoUrl: contact?.photoUrl ?? profile?.photoUrl,
    );
  }

  void _openImageViewer(ChatMessage message, String senderLabel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenImageViewer(
          senderName: message.senderId == _myUid ? 'Você' : senderLabel,
          timeLabel:
              '${DateFormatter.formatDaySeparator(message.effectiveTime)} às ${DateFormatter.formatTime(message.effectiveTime)}',
          chatId: message.chatId,
          mediaId: message.mediaId,
          mimeType: message.mimeType,
          thumbnailBase64: message.thumbnailBase64,
          imageUrl: message.mediaUrl,
          localFilePath: message.localMediaPath,
          caption: message.text,
        ),
      ),
    );
  }

  void _openVideoViewer(ChatMessage message, String senderLabel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoViewer(
          senderName: message.senderId == _myUid ? 'Você' : senderLabel,
          timeLabel:
              '${DateFormatter.formatDaySeparator(message.effectiveTime)} às ${DateFormatter.formatTime(message.effectiveTime)}',
          chatId: message.chatId,
          mediaId: message.mediaId,
          mimeType: message.mimeType,
          localFilePath: message.localMediaPath,
          caption: message.text,
        ),
      ),
    );
  }

  Future<File?> _resolveMessageFile(ChatMessage message) async {
    if (message.localMediaPath != null &&
        File(message.localMediaPath!).existsSync()) {
      return File(message.localMediaPath!);
    }
    if (message.chatId.isEmpty ||
        message.mediaId == null ||
        message.mediaId!.isEmpty) {
      return null;
    }
    return ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
          chatId: message.chatId,
          mediaId: message.mediaId!,
          mimeType: message.mimeType,
          fileName: message.fileName,
        );
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    if (_myUid.isEmpty ||
        message.isUploading ||
        message.uploadFailed ||
        message.deletedForEveryone) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    try {
      await _chatsRepository.toggleReaction(
        chatId: widget.chatId,
        messageId: message.id,
        uid: _myUid,
        emoji: emoji,
        currentReaction: message.reactionFor(_myUid),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message, bottomOffset: 80);
    }
  }

  Future<void> _openForwardSheet(ChatMessage sourceMessage) async {
    final sender =
        _resolveCurrentUser(ref.read(currentUserProfileProvider).value);
    if (sender == null || _myUid.isEmpty) return;

    final target = await showChatForwardSheet(
      context: context,
      myUid: _myUid,
    );

    if (target == null || !mounted) return;

    final targetChatId = ChatIdHelper.buildDirectChatId(_myUid, target.uid);
    final recipient = AppUser(
      uid: target.uid,
      displayName: target.displayName,
      username: target.username,
      about: target.about,
      photoBase64: target.photoBase64,
      photoUrl: target.photoUrl,
    );

    try {
      if (sourceMessage.isText) {
        await _chatsRepository.sendTextMessage(
          chatId: targetChatId,
          sender: sender,
          recipient: recipient,
          text: sourceMessage.text,
          chatExists: target.chatExists,
          isForwarded: true,
        );
      } else {
        final file = await _resolveMessageFile(sourceMessage);
        if (!mounted) return;
        if (file == null || !await file.exists()) {
          throw const AppException('Mídia indisponível para encaminhar.');
        }

        final uploadMgr = ref.read(mediaUploadManagerProvider.notifier);
        if (sourceMessage.isImage) {
          await uploadMgr.enqueuePhotos(
            chatId: targetChatId,
            sender: sender,
            recipient: recipient,
            photos: [(sourcePath: file.path, caption: sourceMessage.text)],
            isForwarded: true,
          );
        } else if (sourceMessage.isVideo) {
          await uploadMgr.enqueueVideo(
            chatId: targetChatId,
            sender: sender,
            recipient: recipient,
            filePath: file.path,
            durationMs: sourceMessage.durationMs ?? 0,
            sizeBytes: await file.length(),
            caption: sourceMessage.text,
            isForwarded: true,
          );
        } else if (sourceMessage.isAudio) {
          await uploadMgr.enqueueAudio(
            chatId: targetChatId,
            sender: sender,
            recipient: recipient,
            filePath: file.path,
            durationMs: sourceMessage.durationMs ?? 0,
            isForwarded: true,
          );
        } else if (sourceMessage.isFile) {
          await uploadMgr.enqueueFile(
            chatId: targetChatId,
            sender: sender,
            recipient: recipient,
            filePath: file.path,
            fileName: sourceMessage.fileName ?? 'arquivo',
            mimeType: sourceMessage.mimeType ?? 'application/octet-stream',
            sizeBytes: await file.length(),
            isForwarded: true,
          );
        } else if (sourceMessage.isSticker) {
          final bytes = await file.readAsBytes();
          await uploadMgr.sendSticker(
            chatId: targetChatId,
            sender: sender,
            recipient: recipient,
            sticker: ZapiSticker(
              id: sourceMessage.mediaId ?? '',
              dataBase64: base64Encode(bytes),
              mimeType: sourceMessage.mimeType ?? 'image/webp',
              sizeBytes: bytes.length,
              isFavorite: false,
            ),
            chatExists: target.chatExists,
            isForwarded: true,
          );
        }
      }

      if (!mounted) return;
      if (targetChatId != widget.chatId) {
        context.pushReplacement('/chats/$targetChatId');
      } else {
        _scrollToBottom();
      }
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message, bottomOffset: 80);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível encaminhar esta mensagem.',
        bottomOffset: 80,
      );
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      _searchMatchIndex = 0;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _jumpToMatch({
    required List<ChatMessage> matches,
    required List<ChatMessage> allMessages,
    required int nextMatchIndex,
  }) {
    if (matches.isEmpty) return;
    final clamped = nextMatchIndex.clamp(0, matches.length - 1);
    setState(() => _searchMatchIndex = clamped);

    final targetMsg = matches[clamped];
    final key = _messageKeys[targetMsg.id];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.4,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final idx = allMessages.indexWhere((m) => m.id == targetMsg.id);
    if (idx >= 0 && _scrollController.hasClients) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimatedOffset = (idx * 78.0).clamp(0.0, maxExtent);
      _scrollController.jumpTo(estimatedOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _messageKeys[targetMsg.id]?.currentContext;
        if (mounted && ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  Future<void> _openFileMessage(ChatMessage message) async {
    final file = await _resolveMessageFile(message);
    if (!mounted) return;
    if (file == null || !await file.exists()) {
      ZapiToast.showError(
        context,
        'Arquivo indisponível.',
        bottomOffset: 80,
      );
      return;
    }
    final res = await OpenFilex.open(
      file.path,
      type: message.mimeType,
    );
    if (!mounted) return;
    if (res.type != ResultType.done) {
      ZapiToast.showError(
        context,
        'Nenhum aplicativo encontrado para abrir este arquivo.',
        bottomOffset: 80,
      );
    }
  }

  Future<void> _shareFileMessage(ChatMessage message) async {
    final file = await _resolveMessageFile(message);
    if (!mounted) return;
    if (file == null || !await file.exists()) {
      ZapiToast.showError(
        context,
        'Arquivo indisponível.',
        bottomOffset: 80,
      );
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      text: message.fileName ?? 'Arquivo',
    );
  }

  void _showMessageActions({
    required ChatMessage message,
    required String senderLabel,
    required bool isLastMessage,
  }) {
    final isMine = message.senderId == _myUid;
    showChatMessageActionsSheet(
      context: context,
      message: message,
      myUid: _myUid,
      senderLabel: senderLabel,
      isLastMessage: isLastMessage,
      onRetryUpload: () => ref
          .read(mediaUploadManagerProvider.notifier)
          .retryUpload(widget.chatId, message.id),
      onCancelUpload: () => ref
          .read(mediaUploadManagerProvider.notifier)
          .cancelUpload(widget.chatId, message.id),
      onToggleReaction: (emoji) => unawaited(_toggleReaction(message, emoji)),
      onReply: () {
        setState(() {
          _replyingTo = ReplyQuote(
            messageId: message.id,
            senderId: message.senderId,
            senderName: isMine ? 'Você' : senderLabel,
            text: message.quotePreviewText,
          );
        });
        _focusNode.requestFocus();
      },
      onForward: () => unawaited(_openForwardSheet(message)),
      onSaveSticker: () async {
        try {
          await ref.read(stickersRepositoryProvider).saveReceivedSticker(
                uid: _myUid,
                chatId: message.chatId,
                mediaId: message.mediaId,
                mimeType: message.mimeType,
              );
        } on AppException catch (e) {
          if (!mounted) return;
          ZapiToast.showError(context, e.message, bottomOffset: 80);
        }
      },
      onOpenFile: () => unawaited(_openFileMessage(message)),
      onSaveFile: () => unawaited(_shareFileMessage(message)),
      onDeleteForMe: () => _hideMessageOptimistically(message.id),
      onDeleteForEveryone: () async {
        try {
          await ref.read(chatsRepositoryProvider).deleteMessageForEveryone(
                chatId: widget.chatId,
                messageId: message.id,
                isLastMessage: isLastMessage,
                mediaId: message.mediaId,
              );
        } on AppException catch (e) {
          if (!mounted) return;
          ZapiToast.showError(context, e.message, bottomOffset: 80);
        }
      },
    );
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> firestoreMessages,
    List<PendingMediaItem> pendingItems,
  ) {
    final visibleFirestore = firestoreMessages
        .where(
          (m) => !m.isHiddenFor(_myUid) && !_pendingHideMessageIds.contains(m.id),
        )
        .toList();
    final existingIds = {for (final m in visibleFirestore) m.id};

    final activePending = pendingItems
        .where((p) => !existingIds.contains(p.id))
        .map((p) => p.toOptimisticMessage())
        .toList();

    final merged = [...activePending, ...visibleFirestore];
    merged.sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProfileProvider).value;
    final thread = ref.watch(chatThreadProvider(widget.chatId)).value;
    final peerUid = _peerUid;
    final peerUser = ref.watch(peerUserProfileProvider(peerUid)).value;
    final savedContact = ref.watch(contactsByUidProvider)[peerUid];
    final presence = ref.watch(userPresenceProvider(peerUid)).value ??
        UserPresence.offline;

    final pendingUploads =
        ref.watch(mediaUploadManagerProvider)[widget.chatId] ?? const [];

    final messagesAsync = ref.watch(
      chatMessagesProvider((chatId: widget.chatId, limit: _messageLimit)),
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final peerName = savedContact?.effectiveName ??
        peerUser?.displayName ??
        thread?.profileFor(peerUid)?.displayName ??
        'Conversa';
    final peerPhotoBase64 = peerUser?.photoBase64 ??
        savedContact?.photoBase64 ??
        thread?.profileFor(peerUid)?.photoBase64;
    final peerPhoto = peerUser?.photoUrl ??
        savedContact?.photoUrl ??
        thread?.profileFor(peerUid)?.photoUrl;

    final isPeerTyping = thread?.isTyping(peerUid) ?? false;
    final hideLastSeen = (currentUser?.hideLastSeen ?? false) ||
        (peerUser?.hideLastSeen ?? false);
    final hideReadReceipts = currentUser?.hideReadReceipts ?? false;
    final statusLabel = isPeerTyping
        ? 'digitando...'
        : hideLastSeen
            ? null
            : (presence.online
                ? 'online'
                : DateFormatter.formatLastSeen(
                    presence.lastSeen ?? peerUser?.lastSeen,
                  ));

    final isBlockedByPeer =
        (peerUser?.blockedUids.contains(_myUid) ?? false) ||
            (thread?.isBlockedBy(peerUid) ?? false);
    final isBlockedByMe =
        (currentUser?.blockedUids.contains(peerUid) ?? false) ||
            (thread?.isBlockedBy(_myUid) ?? false);
    final enterToSend =
        ref.watch(chatPreferencesProvider.select((s) => s.enterToSend));

    ref.listen<ChatPreferencesState>(
      chatPreferencesProvider,
      (_, next) => _applyInitialDraft(next),
    );

    ref.listen<AsyncValue<List<ChatMessage>>>(
      chatMessagesProvider((chatId: widget.chatId, limit: _messageLimit)),
      (previous, next) {
        final rawMessages = next.value;
        if (rawMessages == null) return;

        final nextHasMore = rawMessages.length >= _messageLimit;
        if (_isLoadingMore || _hasMore != nextHasMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _isLoadingMore = false;
              _hasMore = nextHasMore;
            });
          });
        }

        final visible = rawMessages
            .where(
              (m) =>
                  !m.isHiddenFor(_myUid) &&
                  !_pendingHideMessageIds.contains(m.id),
            )
            .toList();

        if (visible.length > _lastVisibleCount && _lastVisibleCount > 0) {
          final newest = visible.first;
          if (newest.senderId == _myUid || _isAtBottom) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hasNewBelow = true);
            });
          }
        }
        _lastVisibleCount = visible.length;

        final latestIncoming = rawMessages
            .where((m) => m.senderId != _myUid && !m.hasPendingWrites)
            .firstOrNull;
        final readToken =
            '${latestIncoming?.id ?? ''}_${thread?.unreadFor(_myUid) ?? 0}_$hideReadReceipts';
        if (_myUid.isNotEmpty && _lastMarkedReadMsgId != readToken) {
          _lastMarkedReadMsgId = readToken;
          ref.read(chatsRepositoryProvider).markChatAsRead(
                chatId: widget.chatId,
                currentUid: _myUid,
                messages: rawMessages,
                thread: thread,
                sendReadReceipt: !hideReadReceipts,
              );
        }
      },
    );

    final cachedMessages = messagesAsync.value;
    final mergedMessages = _mergeMessages(
      cachedMessages ?? const [],
      pendingUploads,
    );
    final trimmedSearch = _searchQuery.trim().toLowerCase();
    final searchMatches = _isSearching && trimmedSearch.isNotEmpty
        ? mergedMessages
            .where(
              (m) =>
                  !m.deletedForEveryone &&
                  m.text.toLowerCase().contains(trimmedSearch),
            )
            .toList()
        : const <ChatMessage>[];
    final safeMatchIdx = searchMatches.isEmpty
        ? 0
        : _searchMatchIndex.clamp(0, searchMatches.length - 1);

    return PopScope(
      canPop: !_showStickerTray && !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          _toggleSearch();
        } else if (_showStickerTray) {
          setState(() => _showStickerTray = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: _isSearching ? null : 0,
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _toggleSearch,
                )
              : null,
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                      _searchMatchIndex = 0;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar nesta conversa...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _searchMatchIndex = 0;
                              });
                            },
                          )
                        : null,
                  ),
                )
              : InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      context.push('/chats/${widget.chatId}/profile'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        ZapiAvatar(
                          displayName: peerName,
                          photoBase64: peerPhotoBase64,
                          photoUrl: peerPhoto,
                          radius: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                peerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (statusLabel != null)
                                Text(
                                  statusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isPeerTyping || presence.online
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isPeerTyping || presence.online
                                        ? (isDark
                                            ? AppColors.emeraldBright
                                            : AppColors.emeraldDark)
                                        : secondaryText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          actions: [
            if (!_isSearching)
              IconButton(
                tooltip: 'Buscar na conversa',
                icon: const Icon(Icons.search_rounded),
                onPressed: _toggleSearch,
              ),
          ],
        ),
        body: Column(
          children: [
            if (_isSearching && trimmedSearch.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  border: Border(
                    bottom: BorderSide(
                      color:
                          isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      searchMatches.isEmpty
                          ? 'Nenhuma mensagem encontrada'
                          : '${safeMatchIdx + 1} de ${searchMatches.length}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: secondaryText,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Ocorrência anterior',
                      visualDensity: VisualDensity.compact,
                      onPressed: searchMatches.isNotEmpty &&
                              safeMatchIdx + 1 < searchMatches.length
                          ? () => _jumpToMatch(
                                matches: searchMatches,
                                allMessages: mergedMessages,
                                nextMatchIndex: safeMatchIdx + 1,
                              )
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Próxima ocorrência',
                      visualDensity: VisualDensity.compact,
                      onPressed: searchMatches.isNotEmpty && safeMatchIdx > 0
                          ? () => _jumpToMatch(
                                matches: searchMatches,
                                allMessages: mergedMessages,
                                nextMatchIndex: safeMatchIdx - 1,
                              )
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ChatAudioMiniBar(chatId: widget.chatId),
            Expanded(
              child: ChatWallpaperBackground(
                preset: ref.watch(chatWallpaperProvider),
                child: Stack(
                  children: [
                  if (cachedMessages == null && messagesAsync.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (cachedMessages == null && messagesAsync.hasError)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Não foi possível carregar as mensagens desta conversa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondaryText),
                        ),
                      ),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final messages = _mergeMessages(
                          cachedMessages ?? const [],
                          pendingUploads,
                        );

                      if (messages.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkSurface
                                        : AppColors.lightSurface,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder,
                                    ),
                                  ),
                                  child: Text(
                                    'Envie uma mensagem, foto, vídeo, arquivo ou figurinha para $peerName.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: secondaryText),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_isLoadingMore && index == messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }

                          final message = messages[index];
                          final messageKey = _messageKeys.putIfAbsent(
                            message.id,
                            () => GlobalKey(),
                          );
                          final olderMessage = index + 1 < messages.length
                              ? messages[index + 1]
                              : null;
                          final showDateChip = olderMessage == null ||
                              !DateFormatter.isSameDay(
                                message.effectiveTime,
                                olderMessage.effectiveTime,
                              );

                          final isLastMessage =
                              thread?.lastMessageId == message.id;

                          return Column(
                            key: messageKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDateChip)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.darkSurface
                                          : AppColors.lightSurface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.darkBorder
                                            : AppColors.lightBorder,
                                      ),
                                    ),
                                    child: Text(
                                      DateFormatter.formatDaySeparator(
                                        message.effectiveTime,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: secondaryText,
                                      ),
                                    ),
                                  ),
                                ),
                              MessageBubble(
                                message: message,
                                isMine: message.senderId == _myUid,
                                currentUid: _myUid,
                                peerUid: peerUid,
                                senderLabel: peerName,
                                highlightQuery: _isSearching ? _searchQuery : '',
                                hideReadReceipts: hideReadReceipts,
                                onReactionTap: (emoji) =>
                                    _toggleReaction(message, emoji),
                                onLongPress: () => _showMessageActions(
                                  message: message,
                                  senderLabel: peerName,
                                  isLastMessage: isLastMessage,
                                ),
                                onImageTap: () =>
                                    _openImageViewer(message, peerName),
                                onVideoTap: () =>
                                    _openVideoViewer(message, peerName),
                                onCancelUpload: message.isUploading ||
                                        message.uploadFailed
                                    ? () => ref
                                        .read(mediaUploadManagerProvider
                                            .notifier)
                                        .cancelUpload(widget.chatId, message.id)
                                    : null,
                                onRetryUpload: message.uploadFailed
                                    ? () => ref
                                        .read(mediaUploadManagerProvider
                                            .notifier)
                                        .retryUpload(widget.chatId, message.id)
                                    : null,
                                onAudioStarted: () {
                                  if (message.senderId != _myUid &&
                                      !message.wasPlayedBy(_myUid)) {
                                    ref
                                        .read(chatsRepositoryProvider)
                                        .markAudioPlayed(
                                          chatId: widget.chatId,
                                          messageId: message.id,
                                          currentUid: _myUid,
                                        );
                                  }
                                },
                              ),
                            ],
                          );
                        },
                        );
                      },
                    ),
                  if (!_isAtBottom || _hasNewBelow)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        tooltip: 'Ir para a última mensagem',
                        onPressed: _scrollToBottom,
                        backgroundColor: isDark
                            ? AppColors.darkSurfaceAlt
                            : AppColors.lightSurface,
                        foregroundColor: AppColors.emerald,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.keyboard_arrow_down_rounded),
                            if (_hasNewBelow)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.emerald,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isBlockedByPeer || isBlockedByMe)
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          isBlockedByMe
                              ? 'Você bloqueou este contato.'
                              : 'Você não pode enviar mensagens para esta conversa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondaryText, fontSize: 13.5),
                        ),
                      ),
                      if (isBlockedByMe) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              context.push('/chats/${widget.chatId}/profile'),
                          child: const Text('Desbloquear'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyingTo != null)
                      ReplyPreviewBar(
                        quote: _replyingTo!,
                        onCancel: () => setState(() => _replyingTo = null),
                      ),
                    if (_voiceController.isActive)
                      VoiceRecordingBar(controller: _voiceController)
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: enterToSend
                                    ? TextInputAction.send
                                    : TextInputAction.newline,
                                onSubmitted: enterToSend
                                    ? (_) => _sendMessage(
                                          currentUser: currentUser,
                                          peerUser: peerUser,
                                          thread: thread,
                                        )
                                    : null,
                                onTap: () {
                                  if (_showStickerTray) {
                                    setState(() => _showStickerTray = false);
                                  }
                                },
                                onChanged: _onTextChanged,
                                decoration: InputDecoration(
                                  hintText: 'Mensagem',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 12,
                                  ),
                                  prefixIcon: IconButton(
                                    tooltip: _showStickerTray
                                        ? 'Teclado'
                                        : 'Emojis e figurinhas',
                                    onPressed: () {
                                      if (_showStickerTray) {
                                        setState(() => _showStickerTray = false);
                                        _focusNode.requestFocus();
                                      } else {
                                        _focusNode.unfocus();
                                        setState(() => _showStickerTray = true);
                                      }
                                    },
                                    icon: Icon(
                                      _showStickerTray
                                          ? Icons.keyboard_rounded
                                          : Icons.sentiment_satisfied_alt_rounded,
                                      color: _showStickerTray
                                          ? AppColors.emerald
                                          : secondaryText,
                                    ),
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: 'Enviar arquivo',
                                    onPressed: () => _pickAndSendFile(
                                      currentUser: currentUser,
                                      peerUser: peerUser,
                                      thread: thread,
                                    ),
                                    icon: Icon(
                                      Icons.attach_file_rounded,
                                      color: secondaryText,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? AppColors.emeraldBright
                                          : AppColors.emerald,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 44,
                              height: 48,
                              child: IconButton(
                                tooltip: 'Câmera e mídia',
                                onPressed: () => _openCameraAndMedia(
                                  currentUser: currentUser,
                                  peerUser: peerUser,
                                  thread: thread,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark
                                      ? AppColors.darkSurfaceAlt
                                      : AppColors.lightSurface,
                                  side: BorderSide(
                                    color: isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                  shape: const CircleBorder(),
                                ),
                                icon: Icon(
                                  Icons.camera_alt_rounded,
                                  color: secondaryText,
                                  size: 21,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (_hasTextInput)
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    shape: const CircleBorder(),
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: _isSending
                                      ? null
                                      : () => _sendMessage(
                                            currentUser: currentUser,
                                            peerUser: peerUser,
                                            thread: thread,
                                          ),
                                  child:
                                      const Icon(Icons.send_rounded, size: 21),
                                ),
                              )
                            else
                              Listener(
                                onPointerDown: (e) => _voiceController
                                    .handlePointerDown(context, e),
                                onPointerMove: _voiceController.handlePointerMove,
                                onPointerUp: (_) =>
                                    _voiceController.handlePointerUpOrCancel(),
                                onPointerCancel: (_) =>
                                    _voiceController.handlePointerUpOrCancel(),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    color: AppColors.emerald,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.mic_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (_showStickerTray && !_voiceController.isActive)
                      StickerTray(
                        onEmojiSelected: _insertEmoji,
                        onStickerSelected: (sticker) async {
                          final effectiveSender =
                              _resolveCurrentUser(currentUser);
                          if (effectiveSender == null) return;
                          final effectivePeer =
                              _resolveEffectivePeer(peerUser, thread);
                          final quote = _replyingTo;
                          if (_replyingTo != null) {
                            setState(() => _replyingTo = null);
                          }
                          try {
                            await ref
                                .read(mediaUploadManagerProvider.notifier)
                                .sendSticker(
                                  chatId: widget.chatId,
                                  sender: effectiveSender,
                                  recipient: effectivePeer,
                                  sticker: sticker,
                                  chatExists: thread != null,
                                  replyTo: quote,
                                );
                            _scrollToBottom();
                          } on AppException catch (e) {
                            if (!mounted) return;
                            ZapiToast.showError(
                              context,
                              e.message,
                              bottomOffset: 80,
                            );
                          }
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
