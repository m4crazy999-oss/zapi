import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../stickers/presentation/widgets/zapi_sticker_image.dart';
import '../../domain/chat_message.dart';

class MessageStatusIcon extends StatelessWidget {
  const MessageStatusIcon({
    super.key,
    required this.status,
    this.size = 15,
  });

  final MessageStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    switch (status) {
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline_rounded,
          size: size,
          color: Theme.of(context).colorScheme.error,
        );
      case MessageStatus.sending:
        return Icon(
          Icons.access_time_rounded,
          size: size - 1,
          color: mutedColor,
        );
      case MessageStatus.sent:
        return Icon(
          Icons.done_rounded,
          size: size,
          color: mutedColor,
        );
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all_rounded,
          size: size,
          color: mutedColor,
        );
      case MessageStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: size,
          color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
        );
    }
  }
}

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.currentUid,
    required this.peerUid,
    required this.onLongPress,
    this.onImageTap,
    this.onCancelUpload,
    this.onRetryUpload,
    this.onAudioStarted,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUid;
  final String peerUid;
  final VoidCallback onLongPress;
  final VoidCallback? onImageTap;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;
  final VoidCallback? onAudioStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (message.isSticker && !message.deletedForEveryone) {
      return _StickerBubble(
        message: message,
        isMine: isMine,
        isDark: isDark,
        onLongPress: onLongPress,
      );
    }

    final bubbleColor = isMine
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final quoteBg = isMine
        ? (isDark
            ? Colors.black.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.05))
        : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: message.isImage && !message.deletedForEveryone
              ? const EdgeInsets.fromLTRB(5, 5, 5, 6)
              : const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            border: isMine
                ? null
                : Border.all(
                    color:
                        isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.8,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyTo != null && !message.deletedForEveryone) ...[
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(
                    bottom: 6,
                    left: message.isImage ? 4 : 0,
                    right: message.isImage ? 4 : 0,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: quoteBg,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: AppColors.emerald, width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.replyTo!.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.emeraldBright
                              : AppColors.emeraldDark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        message.replyTo!.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (message.deletedForEveryone)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.block_rounded,
                      size: 15,
                      color: secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isMine
                          ? 'Você apagou esta mensagem'
                          : 'Mensagem apagada',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: secondaryText,
                      ),
                    ),
                  ],
                )
              else if (message.isImage)
                _ImageBubbleContent(
                  message: message,
                  textColor: textColor,
                  onImageTap: onImageTap,
                  onCancelUpload: onCancelUpload,
                  onRetryUpload: onRetryUpload,
                )
              else if (message.isAudio)
                _AudioBubbleContent(
                  message: message,
                  isMine: isMine,
                  currentUid: currentUid,
                  peerUid: peerUid,
                  isDark: isDark,
                  textColor: textColor,
                  secondaryText: secondaryText,
                  onCancelUpload: onCancelUpload,
                  onRetryUpload: onRetryUpload,
                  onAudioStarted: onAudioStarted,
                )
              else
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.32,
                    color: textColor,
                  ),
                ),
              const SizedBox(height: 3),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: message.isImage && !message.deletedForEveryone
                      ? 5
                      : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      DateFormatter.formatTime(message.effectiveTime),
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryText,
                      ),
                    ),
                    if (isMine && !message.deletedForEveryone) ...[
                      const SizedBox(width: 4),
                      MessageStatusIcon(status: message.effectiveStatus),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerBubble extends StatelessWidget {
  const _StickerBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    required this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isDark;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final pillColor = isDark
        ? Colors.black.withValues(alpha: 0.48)
        : Colors.white.withValues(alpha: 0.85);
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final hasLegacyUrl = (message.assetPath == null || message.assetPath!.isEmpty) &&
        (message.mediaId == null || message.mediaId!.isEmpty) &&
        (message.mediaUrl != null && message.mediaUrl!.isNotEmpty);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              hasLegacyUrl
                  ? Image.network(
                      message.mediaUrl!,
                      width: 148,
                      height: 148,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 148,
                        height: 148,
                        child: Icon(Icons.sticky_note_2_outlined, size: 54),
                      ),
                    )
                  : ZapiStickerImage(
                      assetPath: message.assetPath,
                      chatId: message.chatId,
                      mediaId: message.mediaId,
                      mimeType: message.mimeType ?? 'image/webp',
                      size: 148,
                    ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormatter.formatTime(message.effectiveTime),
                      style: TextStyle(fontSize: 10.5, color: secondaryText),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      MessageStatusIcon(
                        status: message.effectiveStatus,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBubbleContent extends StatelessWidget {
  const _ImageBubbleContent({
    required this.message,
    required this.textColor,
    this.onImageTap,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  final ChatMessage message;
  final Color textColor;
  final VoidCallback? onImageTap;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;

  static final Map<String, Uint8List> _thumbMemoryCache = {};

  Uint8List? _decodeThumb(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final cached = _thumbMemoryCache[raw];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) return null;
      if (_thumbMemoryCache.length > 150) _thumbMemoryCache.clear();
      _thumbMemoryCache[raw] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aspect = (message.width != null &&
            message.height != null &&
            message.height! > 0)
        ? (message.width! / message.height!).clamp(0.62, 1.5)
        : 1.0;

    final localPath = message.localThumbnailPath ?? message.localMediaPath;
    final hasLocal = localPath != null && File(localPath).existsSync();
    final thumbBytes = _decodeThumb(message.thumbnailBase64);
    final legacyNetworkUrl = message.thumbnailUrl ?? message.mediaUrl ?? '';

    Widget imageWidget;
    if (hasLocal) {
      imageWidget = Image.file(
        File(localPath),
        fit: BoxFit.cover,
      );
    } else if (thumbBytes != null) {
      imageWidget = Image.memory(
        thumbBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black12,
          child: Center(child: Icon(Icons.broken_image_outlined, size: 36)),
        ),
      );
    } else if (legacyNetworkUrl.isNotEmpty) {
      imageWidget = Image.network(
        legacyNetworkUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black12,
          child: Center(child: Icon(Icons.broken_image_outlined, size: 36)),
        ),
      );
    } else {
      imageWidget = const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.photo_outlined, size: 36)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: message.isUploading || message.uploadFailed ? null : onImageTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageWidget,
                  if (message.isUploading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: GestureDetector(
                          onTap: onCancelUpload,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              shape: BoxShape.circle,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    value: message.uploadProgress != null &&
                                            message.uploadProgress! > 0
                                        ? message.uploadProgress
                                        : null,
                                    strokeWidth: 3,
                                    color: Colors.white,
                                  ),
                                ),
                                const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (message.uploadFailed)
                    Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              onPressed: onRetryUpload,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.emerald,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Tentar de novo'),
                            ),
                            if (onCancelUpload != null) ...[
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: onCancelUpload,
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (message.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.3,
                color: textColor,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AudioBubbleContent extends ConsumerStatefulWidget {
  const _AudioBubbleContent({
    required this.message,
    required this.isMine,
    required this.currentUid,
    required this.peerUid,
    required this.isDark,
    required this.textColor,
    required this.secondaryText,
    this.onCancelUpload,
    this.onRetryUpload,
    this.onAudioStarted,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUid;
  final String peerUid;
  final bool isDark;
  final Color textColor;
  final Color secondaryText;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;
  final VoidCallback? onAudioStarted;

  @override
  ConsumerState<_AudioBubbleContent> createState() =>
      _AudioBubbleContentState();
}

class _AudioBubbleContentState extends ConsumerState<_AudioBubbleContent> {
  bool _fetchingAudio = false;

  List<double> _buildBars(String seedId) {
    final hash = seedId.hashCode;
    return List.generate(26, (i) {
      final wave = math.sin((i + (hash % 17)) * 0.72).abs();
      return (0.28 + wave * 0.72).clamp(0.24, 1.0);
    });
  }

  Future<void> _handlePlayTap(Duration totalDuration) async {
    if (_fetchingAudio) return;
    final message = widget.message;

    final hasLocal = message.localMediaPath != null &&
        File(message.localMediaPath!).existsSync();

    if (hasLocal) {
      await ref.read(audioPlaybackProvider.notifier).togglePlay(
            messageId: message.id,
            urlOrPath: message.localMediaPath!,
            isLocalFile: true,
            fallbackDuration: totalDuration,
            onStarted: widget.onAudioStarted,
          );
      return;
    }

    if (message.chatId.isNotEmpty &&
        message.mediaId != null &&
        message.mediaId!.isNotEmpty) {
      setState(() => _fetchingAudio = true);
      try {
        final cached =
            await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
                  chatId: message.chatId,
                  mediaId: message.mediaId!,
                  mimeType: message.mimeType ?? 'audio/mp4',
                );
        if (!mounted) return;
        if (cached == null || !await cached.exists()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Áudio indisponível ou apagado.'),
            ),
          );
          return;
        }
        await ref.read(audioPlaybackProvider.notifier).togglePlay(
              messageId: message.id,
              urlOrPath: cached.path,
              isLocalFile: true,
              fallbackDuration: totalDuration,
              onStarted: widget.onAudioStarted,
            );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível baixar este áudio.'),
          ),
        );
      } finally {
        if (mounted) setState(() => _fetchingAudio = false);
      }
      return;
    }

    final legacyUrl = message.mediaUrl ?? '';
    if (legacyUrl.isEmpty) return;
    await ref.read(audioPlaybackProvider.notifier).togglePlay(
          messageId: message.id,
          urlOrPath: legacyUrl,
          isLocalFile: false,
          fallbackDuration: totalDuration,
          onStarted: widget.onAudioStarted,
        );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final playback = ref.watch(audioPlaybackProvider);
    final isActive = playback.activeMessageId == message.id;
    final totalDuration = isActive && playback.duration > Duration.zero
        ? playback.duration
        : Duration(milliseconds: message.durationMs ?? 0);
    final currentPos = isActive ? playback.position : Duration.zero;
    final progressRatio = totalDuration.inMilliseconds > 0
        ? (currentPos.inMilliseconds / totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final wasListened = widget.isMine
        ? message.wasPlayedBy(widget.peerUid)
        : message.wasPlayedBy(widget.currentUid);
    final micColor = wasListened
        ? (widget.isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
        : widget.secondaryText;

    final displayDuration =
        isActive && (playback.isPlaying || currentPos > Duration.zero)
            ? currentPos
            : totalDuration;

    final bars = _buildBars(message.id);
    final activeBarColor = AppColors.emerald;
    final idleBarColor = widget.secondaryText.withValues(alpha: 0.35);

    Widget leadingControl;
    if (message.isUploading) {
      leadingControl = GestureDetector(
        onTap: widget.onCancelUpload,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: message.uploadProgress != null &&
                        message.uploadProgress! > 0
                    ? message.uploadProgress
                    : null,
                strokeWidth: 2.8,
                color: AppColors.emerald,
              ),
              Icon(Icons.close_rounded, size: 18, color: widget.textColor),
            ],
          ),
        ),
      );
    } else if (message.uploadFailed) {
      leadingControl = IconButton(
        onPressed: widget.onRetryUpload,
        tooltip: 'Tentar enviar novamente',
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.refresh_rounded,
          color: Theme.of(context).colorScheme.error,
          size: 28,
        ),
      );
    } else {
      leadingControl = InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _handlePlayTap(totalDuration),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: _fetchingAudio || (isActive && playback.isLoading)
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.emerald,
                  ),
                )
              : Icon(
                  isActive && playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: AppColors.emerald,
                  size: 26,
                ),
        ),
      );
    }

    return SizedBox(
      width: 232,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              leadingControl,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: isActive && totalDuration > Duration.zero
                              ? (details) {
                                  final fraction = (details.localPosition.dx /
                                          constraints.maxWidth)
                                      .clamp(0.0, 1.0);
                                  final target = Duration(
                                    milliseconds:
                                        (totalDuration.inMilliseconds *
                                                fraction)
                                            .round(),
                                  );
                                  ref
                                      .read(audioPlaybackProvider.notifier)
                                      .seek(message.id, target);
                                }
                              : null,
                          child: SizedBox(
                            height: 26,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: List.generate(bars.length, (idx) {
                                final barFrac = idx / bars.length;
                                final filled =
                                    isActive && barFrac <= progressRatio;
                                return Container(
                                  width: 3,
                                  height: 22 * bars[idx],
                                  decoration: BoxDecoration(
                                    color:
                                        filled ? activeBarColor : idleBarColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.mic_rounded, size: 14, color: micColor),
                        const SizedBox(width: 4),
                        Text(
                          message.uploadFailed
                              ? 'Falha no envio'
                              : DateFormatter.formatDuration(displayDuration),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: message.uploadFailed
                                ? Theme.of(context).colorScheme.error
                                : widget.secondaryText,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        if (isActive)
                          GestureDetector(
                            onTap: () => ref
                                .read(audioPlaybackProvider.notifier)
                                .cycleSpeed(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.emerald.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                playback.speed == 1.0
                                    ? '1x'
                                    : (playback.speed == 1.5 ? '1.5x' : '2x'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: widget.isDark
                                      ? AppColors.emeraldBright
                                      : AppColors.emeraldDark,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
