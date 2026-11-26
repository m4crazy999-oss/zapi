import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../stickers/presentation/providers/stickers_providers.dart';
import '../../../stickers/presentation/widgets/sticker_tray.dart';
import '../../data/chats_repository.dart';
import '../../data/media_upload_manager.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_thread.dart';
import '../providers/chats_providers.dart';
import '../widgets/attachment_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/reply_preview_bar.dart';
import '../widgets/voice_recorder_bar.dart';
import 'fullscreen_image_viewer.dart';
import 'image_preview_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
  });

  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();

  int _messageLimit = AppConstants.messagesPageSize;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isAtBottom = true;
  bool _hasNewBelow = false;
  bool _isSending = false;
  bool _isCurrentlyTyping = false;
  bool _hasTextInput = false;
  bool _showStickerTray = false;
  int _lastVisibleCount = 0;

  Timer? _typingTimer;
  ReplyQuote? _replyingTo;
  late final NotificationService _notificationService;
  late final ChatsRepository _chatsRepository;
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
    _audioController = ref.read(audioPlaybackProvider.notifier);
    _notificationService.setActiveChatId(widget.chatId);
    _scrollController.addListener(_onScroll);

    _voiceController = VoiceRecorderController(
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      onFeedbackMessage: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      },
      onCompleted: _handleRecordedVoice,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
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
    _focusNode.dispose();
    super.dispose();
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

  Future<void> _sendMessage({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending || currentUser == null) return;

    final effectivePeer = _resolveEffectivePeer(peerUser, thread);
    final quote = _replyingTo;
    _textController.clear();
    _stopTypingNow();
    setState(() {
      _hasTextInput = false;
      _replyingTo = null;
      _isSending = true;
    });

    try {
      await ref.read(chatsRepositoryProvider).sendTextMessage(
            chatId: widget.chatId,
            sender: currentUser,
            recipient: effectivePeer,
            text: text,
            chatExists: thread != null,
            replyTo: quote,
          );
      _scrollToBottom();
    } on AppException catch (e) {
      if (!mounted) return;
      _textController.text = text;
      setState(() => _hasTextInput = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _openAttachmentMenu({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    if (currentUser == null) return;
    _focusNode.unfocus();
    final action = await AttachmentSheet.show(context);
    if (action == null || !mounted) return;

    switch (action) {
      case AttachmentAction.camera:
        await _pickCameraPhoto(
          currentUser: currentUser,
          peerUser: peerUser,
          thread: thread,
        );
      case AttachmentAction.gallery:
        await _pickGalleryPhotos(
          currentUser: currentUser,
          peerUser: peerUser,
          thread: thread,
        );
      case AttachmentAction.stickers:
        setState(() => _showStickerTray = true);
    }
  }

  Future<void> _pickCameraPhoto({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    if (currentUser == null) return;
    final granted = await PermissionHelper.requestCamera(context);
    if (!granted || !mounted) return;

    try {
      final shot = await _imagePicker.pickImage(source: ImageSource.camera);
      if (shot == null || !mounted) return;
      await _openPreviewAndEnqueue(
        paths: [shot.path],
        currentUser: currentUser,
        peerUser: peerUser,
        thread: thread,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a câmera.')),
      );
    }
  }

  Future<void> _pickGalleryPhotos({
    required AppUser? currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    if (currentUser == null) return;
    final granted = await PermissionHelper.requestGallery(context);
    if (!granted || !mounted) return;

    try {
      final selected = await _imagePicker.pickMultiImage(limit: 10);
      if (selected.isEmpty || !mounted) return;
      await _openPreviewAndEnqueue(
        paths: selected.map((x) => x.path).toList(),
        currentUser: currentUser,
        peerUser: peerUser,
        thread: thread,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir a galeria.')),
      );
    }
  }

  Future<void> _openPreviewAndEnqueue({
    required List<String> paths,
    required AppUser currentUser,
    required AppUser? peerUser,
    required ChatThread? thread,
  }) async {
    final effectivePeer = _resolveEffectivePeer(peerUser, thread);
    final result = await Navigator.push<
        List<({String sourcePath, String caption})>>(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewScreen(
          initialPaths: paths,
          recipientName: effectivePeer.displayName,
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final quote = _replyingTo;
    setState(() {
      _replyingTo = null;
      _showStickerTray = false;
    });

    await ref.read(mediaUploadManagerProvider.notifier).enqueuePhotos(
          chatId: widget.chatId,
          sender: currentUser,
          recipient: effectivePeer,
          photos: result,
          replyTo: quote,
        );
    _scrollToBottom();
  }

  Future<void> _handleRecordedVoice(String filePath, int durationMs) async {
    final currentUser = ref.read(currentUserProfileProvider).value;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
      email: '',
      about: contact?.about ?? '',
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

  void _showMessageActions({
    required ChatMessage message,
    required String senderLabel,
    required bool isLastMessage,
  }) {
    final isMine = message.senderId == _myUid;

    if (message.isUploading || message.uploadFailed) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.uploadFailed)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Tentar enviar novamente'),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      ref
                          .read(mediaUploadManagerProvider.notifier)
                          .retryUpload(widget.chatId, message.id);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.close_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    message.uploadFailed ? 'Descartar envio' : 'Cancelar envio',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ref
                        .read(mediaUploadManagerProvider.notifier)
                        .cancelUpload(widget.chatId, message.id);
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.deletedForEveryone) ...[
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Responder'),
                  onTap: () {
                    Navigator.pop(sheetContext);
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
                ),
                if (message.isSticker &&
                    ((message.assetPath?.isNotEmpty ?? false) ||
                        (message.mediaId?.isNotEmpty ?? false)))
                  ListTile(
                    leading: const Icon(Icons.star_outline_rounded),
                    title: const Text('Adicionar às minhas figurinhas'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await ref
                            .read(stickersRepositoryProvider)
                            .saveReceivedSticker(
                              uid: _myUid,
                              assetPath: message.assetPath,
                              chatId: message.chatId,
                              mediaId: message.mediaId,
                              mimeType: message.mimeType,
                            );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Figurinha salva em suas figurinhas!'),
                          ),
                        );
                      } on AppException catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                        );
                      }
                    },
                  ),
                if (message.text.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copiar texto'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Clipboard.setData(
                        ClipboardData(text: message.text),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Texto copiado.')),
                      );
                    },
                  ),
              ],
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Apagar para mim'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await ref.read(chatsRepositoryProvider).deleteMessageForMe(
                          chatId: widget.chatId,
                          messageId: message.id,
                          uid: _myUid,
                        );
                  } on AppException catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                },
              ),
              if (isMine && !message.deletedForEveryone)
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Apagar para todos',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await ref
                          .read(chatsRepositoryProvider)
                          .deleteMessageForEveryone(
                            chatId: widget.chatId,
                            messageId: message.id,
                            isLastMessage: isLastMessage,
                            mediaId: message.mediaId,
                          );
                    } on AppException catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.message),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> firestoreMessages,
    List<PendingMediaItem> pendingItems,
  ) {
    final visibleFirestore =
        firestoreMessages.where((m) => !m.isHiddenFor(_myUid)).toList();
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
    final statusLabel = isPeerTyping
        ? 'digitando...'
        : (presence.online
            ? 'online'
            : DateFormatter.formatLastSeen(
                presence.lastSeen ?? peerUser?.lastSeen,
              ));

    final isBlockedByPeer =
        (peerUser?.blockedUids.contains(_myUid) ?? false) ||
            (thread?.isBlockedBy(peerUid) ?? false);

    ref.listen<AsyncValue<List<ChatMessage>>>(
      chatMessagesProvider((chatId: widget.chatId, limit: _messageLimit)),
      (previous, next) {
        final rawMessages = next.value;
        if (rawMessages == null) return;

        if (_isLoadingMore || rawMessages.length < _messageLimit) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _isLoadingMore = false;
              _hasMore = rawMessages.length >= _messageLimit;
            });
          });
        }

        final visible =
            rawMessages.where((m) => !m.isHiddenFor(_myUid)).toList();

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

        if (_myUid.isNotEmpty) {
          ref.read(chatsRepositoryProvider).markChatAsRead(
                chatId: widget.chatId,
                currentUid: _myUid,
                messages: rawMessages,
                thread: thread,
              );
        }
      },
    );

    return PopScope(
      canPop: !_showStickerTray,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showStickerTray) {
          setState(() => _showStickerTray = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
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
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  messagesAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Não foi possível carregar as mensagens desta conversa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondaryText),
                        ),
                      ),
                    ),
                    data: (rawMessages) {
                      final messages =
                          _mergeMessages(rawMessages, pendingUploads);

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
                                    'Envie uma mensagem, foto, áudio ou figurinha para $peerName.',
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
                                onLongPress: () => _showMessageActions(
                                  message: message,
                                  senderLabel: peerName,
                                  isLastMessage: isLastMessage,
                                ),
                                onImageTap: () =>
                                    _openImageViewer(message, peerName),
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
                  if (_hasNewBelow)
                    Positioned(
                      right: 16,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        onPressed: _scrollToBottom,
                        backgroundColor: isDark
                            ? AppColors.darkSurfaceAlt
                            : AppColors.lightSurface,
                        foregroundColor: AppColors.emerald,
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                ],
              ),
            ),
            if (isBlockedByPeer)
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  child: Text(
                    'Você não pode enviar mensagens para esta conversa.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondaryText, fontSize: 13.5),
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
                    if (_voiceController.isRecording)
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
                                        : 'Figurinhas',
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
                                          : Icons.sticky_note_2_outlined,
                                      color: _showStickerTray
                                          ? AppColors.emerald
                                          : secondaryText,
                                    ),
                                  ),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Anexar mídia',
                                        onPressed: () => _openAttachmentMenu(
                                          currentUser: currentUser,
                                          peerUser: peerUser,
                                          thread: thread,
                                        ),
                                        icon: Icon(
                                          Icons.attach_file_rounded,
                                          color: secondaryText,
                                        ),
                                      ),
                                      if (!_hasTextInput)
                                        IconButton(
                                          tooltip: 'Câmera',
                                          onPressed: () => _pickCameraPhoto(
                                            currentUser: currentUser,
                                            peerUser: peerUser,
                                            thread: thread,
                                          ),
                                          icon: Icon(
                                            Icons.camera_alt_outlined,
                                            color: secondaryText,
                                          ),
                                        ),
                                    ],
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
                            const SizedBox(width: 8),
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
                    if (_showStickerTray && !_voiceController.isRecording)
                      StickerTray(
                        onStickerSelected: (sticker) async {
                          if (currentUser == null) return;
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
                                  sender: currentUser,
                                  recipient: effectivePeer,
                                  sticker: sticker,
                                  chatExists: thread != null,
                                  replyTo: quote,
                                );
                            _scrollToBottom();
                          } on AppException catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.message),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
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
