import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/editor/editor_models.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chats/domain/chat_message.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/status_item.dart';
import '../providers/status_providers.dart';

class StatusViewerScreen extends ConsumerStatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
    this.isMine = false,
  });

  final List<ContactStatusGroup> groups;
  final int initialGroupIndex;
  final bool isMine;

  @override
  ConsumerState<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends ConsumerState<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(seconds: 6);

  late final List<ContactStatusGroup> _groups;
  late final AnimationController _progressController;
  late int _groupIndex;
  int _itemIndex = 0;
  bool _isPaused = false;
  bool _isDeleting = false;

  final Map<String, Uint8List> _decodedImageCache = {};
  final Map<String, String> _decodedVideoPaths = {};
  final Set<String> _recordedViewIds = {};

  VideoPlayerController? _videoController;
  String? _videoControllerStatusId;
  bool _loadingVideo = false;
  bool _videoError = false;
  int _videoInitGeneration = 0;

  @override
  void initState() {
    super.initState();
    _groups = widget.groups
        .map(
          (g) => ContactStatusGroup(
            ownerUid: g.ownerUid,
            displayName: g.displayName,
            username: g.username,
            photoBase64: g.photoBase64,
            statuses: List<StatusItem>.from(g.statuses),
            hasUnviewed: g.hasUnviewed,
            isMuted: g.isMuted,
          ),
        )
        .toList();

    _groupIndex = widget.initialGroupIndex.clamp(
      0,
      (_groups.length - 1).clamp(0, _groups.length),
    );

    if (_groups.isNotEmpty && !widget.isMine) {
      final prefs = ref.read(chatPreferencesProvider);
      final statuses = _groups[_groupIndex].statuses;
      final firstUnviewed =
          statuses.indexWhere((s) => !prefs.isStatusViewed(s.id));
      if (firstUnviewed >= 0) {
        _itemIndex = firstUnviewed;
      }
    }

    _progressController = AnimationController(
      vsync: this,
      duration: _slideDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _next();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentStatus == null) return;
      _activateCurrentSlide();
    });
  }

  @override
  void dispose() {
    _videoInitGeneration++;
    _progressController.dispose();
    _videoController?.dispose();
    _decodedImageCache.clear();
    super.dispose();
  }

  ContactStatusGroup? get _currentGroup {
    if (_groups.isEmpty || _groupIndex < 0 || _groupIndex >= _groups.length) {
      return null;
    }
    return _groups[_groupIndex];
  }

  StatusItem? get _currentStatus {
    final group = _currentGroup;
    if (group == null ||
        group.statuses.isEmpty ||
        _itemIndex < 0 ||
        _itemIndex >= group.statuses.length) {
      return null;
    }
    return group.statuses[_itemIndex];
  }

  Uint8List? _decodeStatusImage(StatusItem item) {
    final raw = item.imageBase64?.trim();
    if (raw == null || raw.isEmpty) return null;
    final cached = _decodedImageCache[item.id];
    if (cached != null) return cached;
    try {
      final clean = raw.contains(',') ? raw.split(',').last : raw;
      final bytes = base64Decode(clean);
      if (bytes.isEmpty) return null;
      _decodedImageCache[item.id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _markCurrentAsViewed() {
    final item = _currentStatus;
    if (item == null || widget.isMine) return;

    unawaited(
      ref.read(chatPreferencesProvider.notifier).markStatusViewed(item.id),
    );

    if (_recordedViewIds.contains(item.id)) return;
    _recordedViewIds.add(item.id);

    final viewer = ref.read(currentUserProfileProvider).value;
    if (viewer == null || viewer.uid == item.ownerUid) return;

    unawaited(
      ref.read(statusRepositoryProvider).recordView(status: item, viewer: viewer),
    );
  }

  Future<void> _activateCurrentSlide() async {
    final item = _currentStatus;
    if (item == null || !mounted) return;

    _markCurrentAsViewed();
    _isPaused = false;

    final prevController = _videoController;
    _videoController = null;
    _videoControllerStatusId = null;
    if (prevController != null) {
      unawaited(prevController.dispose());
    }

    if (!item.isVideo) {
      _loadingVideo = false;
      _videoError = false;
      _progressController.duration = _slideDuration;
      _progressController.forward(from: 0);
      if (mounted) setState(() {});
      return;
    }

    final gen = ++_videoInitGeneration;
    _progressController.stop();
    _progressController.value = 0;
    setState(() {
      _loadingVideo = true;
      _videoError = false;
    });

    try {
      final videoPath = await _ensureVideoTempFile(item);
      if (!mounted || gen != _videoInitGeneration) return;
      if (videoPath == null) {
        setState(() {
          _loadingVideo = false;
          _videoError = true;
        });
        _progressController.duration = _slideDuration;
        _progressController.forward(from: 0);
        return;
      }

      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      if (!mounted || gen != _videoInitGeneration) {
        await controller.dispose();
        return;
      }

      final rawDur = controller.value.duration;
      final clampedMs = (rawDur.inMilliseconds > 0
              ? rawDur.inMilliseconds
              : (item.durationMs ?? 6000))
          .clamp(1200, 60000);
      _progressController.duration = Duration(milliseconds: clampedMs);

      setState(() {
        _videoController = controller;
        _videoControllerStatusId = item.id;
        _loadingVideo = false;
      });
      await controller.play();
      if (mounted && gen == _videoInitGeneration && !_isPaused) {
        _progressController.forward(from: 0);
      }
    } catch (_) {
      if (!mounted || gen != _videoInitGeneration) return;
      setState(() {
        _loadingVideo = false;
        _videoError = true;
      });
      _progressController.duration = _slideDuration;
      _progressController.forward(from: 0);
    }
  }

  Future<String?> _ensureVideoTempFile(StatusItem item) async {
    final cachedPath = _decodedVideoPaths[item.id];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }
    final raw = item.videoBase64?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final clean = raw.contains(',') ? raw.split(',').last : raw;
      final bytes = base64Decode(clean);
      if (bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final videoDir = Directory(p.join(dir.path, 'zapi_status_videos'));
      if (!await videoDir.exists()) {
        await videoDir.create(recursive: true);
      }
      final safeId = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File(p.join(videoDir.path, '$safeId.mp4'));
      await file.writeAsBytes(bytes, flush: true);
      _decodedVideoPaths[item.id] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _pause() {
    if (_isPaused) return;
    _isPaused = true;
    _progressController.stop();
    if (_videoController != null && _videoController!.value.isInitialized) {
      unawaited(_videoController!.pause());
    }
  }

  void _resume() {
    if (!_isPaused || !mounted) return;
    _isPaused = false;
    _progressController.forward();
    if (_videoController != null && _videoController!.value.isInitialized) {
      unawaited(_videoController!.play());
    }
  }

  void _next() {
    final group = _currentGroup;
    if (group == null) {
      Navigator.pop(context);
      return;
    }

    if (_itemIndex + 1 < group.statuses.length) {
      setState(() => _itemIndex++);
    } else if (_groupIndex + 1 < _groups.length) {
      setState(() {
        _groupIndex++;
        _itemIndex = 0;
      });
    } else {
      Navigator.pop(context);
      return;
    }

    unawaited(_activateCurrentSlide());
  }

  void _previous() {
    if (_itemIndex > 0) {
      setState(() => _itemIndex--);
    } else if (_groupIndex > 0) {
      final prevGroupIndex = _groupIndex - 1;
      setState(() {
        _groupIndex = prevGroupIndex;
        _itemIndex = (_groups[prevGroupIndex].statuses.length - 1).clamp(0, 999);
      });
    } else {
      unawaited(_activateCurrentSlide());
      return;
    }

    unawaited(_activateCurrentSlide());
  }

  String _formatStatusTimestamp(DateTime createdAt) {
    final day = DateFormatter.formatDaySeparator(createdAt).toLowerCase();
    final time = DateFormatter.formatTime(createdAt);
    return '$day às $time';
  }

  Future<void> _deleteCurrent() async {
    final current = _currentStatus;
    final group = _currentGroup;
    if (current == null || group == null || _isDeleting) return;

    _pause();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir status?'),
        content: const Text('Este status será apagado para todos agora mesmo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      _resume();
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await ref.read(statusRepositoryProvider).deleteStatus(current.id);
      if (!mounted) return;
      group.statuses.removeAt(_itemIndex);
      if (group.statuses.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        if (_itemIndex >= group.statuses.length) {
          _itemIndex = group.statuses.length - 1;
        }
      });
      unawaited(_activateCurrentSlide());
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
      _resume();
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _openViewersSheet(StatusItem status) async {
    _pause();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final viewsAsync = sheetRef.watch(statusViewsProvider(status.id));
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          viewsAsync.when(
                            data: (list) =>
                                'Visualizado por ${list.length}',
                            loading: () => 'Visualizações',
                            error: (_, __) => 'Visualizações',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: viewsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Não foi possível carregar as visualizações.'),
                      ),
                      data: (views) {
                        if (views.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 28,
                            ),
                            child: Text(
                              'Ninguém visualizou este status ainda.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: views.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 72),
                          itemBuilder: (context, idx) {
                            final view = views[idx];
                            return ListTile(
                              leading: ZapiAvatar(
                                displayName: view.viewerName,
                                photoBase64: view.viewerPhotoBase64,
                                radius: 22,
                              ),
                              title: Text(view.viewerName),
                              subtitle: Text(
                                _formatStatusTimestamp(view.viewedAt),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    _resume();
  }

  void _replyToStatus(StatusItem status, ContactStatusGroup group) {
    final myUid = ref.read(authStateProvider).value?.uid ?? '';
    if (myUid.isEmpty || status.ownerUid == myUid) return;

    final chatId = ChatIdHelper.buildDirectChatId(myUid, status.ownerUid);
    final quote = ReplyQuote(
      messageId: status.id,
      senderId: status.ownerUid,
      senderName: group.displayName,
      text: status.replyPreviewLabel,
    );

    Navigator.pop(context);
    context.push('/chats/$chatId', extra: quote);
  }

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final current = _currentStatus;
    if (group == null || current == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    final myUid = ref.watch(authStateProvider).value?.uid ?? '';
    final isMuted = ref.watch(
      chatPreferencesProvider.select((p) => p.isStatusMuted(group.ownerUid)),
    );
    final ownViewsCount = widget.isMine
        ? (ref.watch(statusViewsProvider(current.id)).value?.length ?? 0)
        : 0;
    final imageBytes = (current.isImage ||
            (current.isText && (current.imageBase64?.isNotEmpty ?? false)))
        ? _decodeStatusImage(current)
        : null;

    final bgStart = current.isText
        ? Color(current.backgroundColor)
        : AppColors.darkBackground;
    final bgEnd = current.isText && current.backgroundGradientEnd != null
        ? Color(current.backgroundGradientEnd!)
        : null;
    final textAlign = switch (current.textAlign) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final baseFontSize = current.text.length > 140
        ? (current.fontSize * 0.82).clamp(16.0, 32.0)
        : current.fontSize;
    final statusTextColor = Color(current.textColor ?? 0xFFFFFFFF);
    final textStyle = buildEditorOverlayTextStyle(
      fontKey: current.fontStyle,
      color: statusTextColor,
      fontSize: baseFontSize,
      withShadow: imageBytes != null || !current.withPill,
      isBold: current.isBold,
      isItalic: current.isItalic,
    ).copyWith(height: 1.32);
    final pillColor = statusTextColor.computeLuminance() > 0.6
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.85);

    return Scaffold(
      backgroundColor: bgStart,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onTapUp: (details) {
          final width = MediaQuery.sizeOf(context).width;
          if (details.localPosition.dx < width * 0.30) {
            _previous();
          } else {
            _next();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: bgEnd == null ? bgStart : null,
            gradient: bgEnd != null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [bgStart, bgEnd],
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (current.isImage)
                imageBytes != null
                    ? Center(
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      )
                    : const Center(
                        child: Text(
                          'Não foi possível abrir esta imagem.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
              else if (current.isVideo)
                if (_loadingVideo)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (_videoError ||
                    _videoController == null ||
                    _videoControllerStatusId != current.id ||
                    !_videoController!.value.isInitialized)
                  const Center(
                    child: Text(
                      'Não foi possível reproduzir este vídeo.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio > 0
                          ? _videoController!.value.aspectRatio
                          : 9 / 16,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cw = constraints.maxWidth;
                    final ch = constraints.maxHeight;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageBytes != null) ...[
                          Image.memory(
                            imageBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ],
                        Positioned(
                          left: current.textPosX * cw,
                          top: current.textPosY * ch,
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, -0.5),
                            child: Transform.rotate(
                              angle: current.textRotation,
                              child: Transform.scale(
                                scale: current.textScale,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: cw * 0.86,
                                  ),
                                  padding: current.withPill
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        )
                                      : const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                  decoration: current.withPill
                                      ? BoxDecoration(
                                          color: pillColor,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        )
                                      : null,
                                  child: Text(
                                    current.text,
                                    textAlign: textAlign,
                                    style: textStyle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

            // Barra superior sutil para legibilidade dos controles sobre fotos claras
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 136,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Barras de progresso + cabeçalho
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) {
                        return Row(
                          children: [
                            for (var i = 0; i < group.statuses.length; i++) ...[
                              if (i > 0) const SizedBox(width: 4),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    minHeight: 3,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.3),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                    value: i < _itemIndex
                                        ? 1.0
                                        : (i == _itemIndex
                                            ? _progressController.value
                                            : 0.0),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                          ),
                        ),
                        ZapiAvatar(
                          displayName: group.displayName,
                          photoBase64: group.photoBase64,
                          radius: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isMine
                                    ? 'Meu status'
                                    : group.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                ),
                              ),
                              Text(
                                _formatStatusTimestamp(current.createdAt),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.isMine)
                          IconButton(
                            tooltip: 'Excluir status',
                            onPressed: _isDeleting ? null : _deleteCurrent,
                            icon: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          )
                        else
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
                            ),
                            onOpened: _pause,
                            onCanceled: _resume,
                            onSelected: (value) async {
                              if (value == 'mute') {
                                await ref
                                    .read(chatPreferencesProvider.notifier)
                                    .setStatusMuted(group.ownerUid, !isMuted);
                                _resume();
                              } else if (value == 'profile' &&
                                  myUid.isNotEmpty) {
                                final chatId = ChatIdHelper.buildDirectChatId(
                                  myUid,
                                  group.ownerUid,
                                );
                                if (!mounted) return;
                                Navigator.pop(context);
                                context.push('/chats/$chatId/profile');
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'mute',
                                child: Text(
                                  isMuted
                                      ? 'Reativar status'
                                      : 'Silenciar status',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'profile',
                                child: Text('Ver perfil'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Legenda (para fotos) e barra inferior (Visualizações ou Responder)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((current.isImage || current.isVideo) &&
                          current.text.trim().isNotEmpty) ...[
                        Text(
                          current.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (widget.isMine)
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _openViewersSheet(current),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.visibility_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ownViewsCount == 1
                                      ? '1 visualização'
                                      : '$ownViewsCount visualizações',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () => _replyToStatus(current, group),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 12,
                            ),
                          ),
                          icon: const Icon(Icons.reply_rounded, size: 19),
                          label: const Text('Responder'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
