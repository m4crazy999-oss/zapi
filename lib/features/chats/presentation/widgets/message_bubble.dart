import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
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
          Icons.error_rounded,
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
    this.onVideoTap,
    this.onCancelUpload,
    this.onRetryUpload,
    this.onAudioStarted,
    this.onReactionTap,
    this.highlightQuery = '',
    this.hideReadReceipts = false,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUid;
  final String peerUid;
  final VoidCallback onLongPress;
  final VoidCallback? onImageTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;
  final VoidCallback? onAudioStarted;
  final ValueChanged<String>? onReactionTap;
  final String highlightQuery;
  final bool hideReadReceipts;

  MessageStatus _visibleStatus() {
    final raw = message.effectiveStatus;
    if (hideReadReceipts && raw == MessageStatus.read) {
      return MessageStatus.delivered;
    }
    return raw;
  }

  Widget _buildHighlightedText({
    required String text,
    required TextStyle baseStyle,
    required bool isDark,
  }) {
    final query = highlightQuery.trim();
    if (query.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (start < text.length) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
            backgroundColor: isDark
                ? const Color(0xFFFACC15).withValues(alpha: 0.38)
                : const Color(0xFFFEF08A),
            color: isDark ? Colors.white : AppColors.lightTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = idx + query.length;
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (message.isSticker && !message.deletedForEveryone) {
      return _StickerBubble(
        message: message,
        isMine: isMine,
        currentUid: currentUid,
        isDark: isDark,
        visibleStatus: _visibleStatus(),
        onLongPress: onLongPress,
        onReactionTap: onReactionTap,
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

    final compactMedia =
        (message.isImage || message.isVideo) && !message.deletedForEveryone;
    final reactionCounts = message.deletedForEveryone
        ? const <String, int>{}
        : message.reactionCounts;
    final myReaction = message.reactionFor(currentUid);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  padding: compactMedia
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
                            color: isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                            width: 0.8,
                          ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isForwarded &&
                          !message.deletedForEveryone) ...[
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: 4,
                            left: compactMedia ? 4 : 0,
                            right: compactMedia ? 4 : 0,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.forward_rounded,
                                size: 13,
                                color: secondaryText,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Encaminhada',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (message.replyTo != null &&
                          !message.deletedForEveryone) ...[
                        Container(
                          width: double.infinity,
                          margin: EdgeInsets.only(
                            bottom: 6,
                            left: compactMedia ? 4 : 0,
                            right: compactMedia ? 4 : 0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: quoteBg,
                            borderRadius: BorderRadius.circular(8),
                            border: const Border(
                              left: BorderSide(
                                color: AppColors.emerald,
                                width: 3,
                              ),
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
                      else if (message.isVideo)
                        _VideoBubbleContent(
                          message: message,
                          textColor: textColor,
                          onVideoTap: onVideoTap,
                          onCancelUpload: onCancelUpload,
                          onRetryUpload: onRetryUpload,
                        )
                      else if (message.isFile)
                        _FileBubbleContent(
                          message: message,
                          isMine: isMine,
                          isDark: isDark,
                          textColor: textColor,
                          secondaryText: secondaryText,
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
                        _buildHighlightedText(
                          text: message.text,
                          baseStyle: TextStyle(
                            fontSize: 15,
                            height: 1.32,
                            color: textColor,
                          ),
                          isDark: isDark,
                        ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compactMedia ? 5 : 0,
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
                              MessageStatusIcon(status: _visibleStatus()),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (reactionCounts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _ReactionsStrip(
                    counts: reactionCounts,
                    myReaction: myReaction,
                    isDark: isDark,
                    onTap: onReactionTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionsStrip extends StatelessWidget {
  const _ReactionsStrip({
    required this.counts,
    required this.myReaction,
    required this.isDark,
    this.onTap,
  });

  final Map<String, int> counts;
  final String? myReaction;
  final bool isDark;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: counts.entries.map((entry) {
        final selected = myReaction == entry.key;
        return GestureDetector(
          onTap: onTap == null ? null : () => onTap!(entry.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.emerald.withValues(alpha: isDark ? 0.28 : 0.16)
                  : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.emerald
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                if (entry.value > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '${entry.value}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.emerald
                          : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StickerBubble extends StatelessWidget {
  const _StickerBubble({
    required this.message,
    required this.isMine,
    required this.currentUid,
    required this.isDark,
    required this.visibleStatus,
    required this.onLongPress,
    this.onReactionTap,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUid;
  final bool isDark;
  final MessageStatus visibleStatus;
  final VoidCallback onLongPress;
  final ValueChanged<String>? onReactionTap;

  @override
  Widget build(BuildContext context) {
    final pillColor = isDark
        ? Colors.black.withValues(alpha: 0.48)
        : Colors.white.withValues(alpha: 0.85);
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final hasLegacyUrl = (message.mediaId == null || message.mediaId!.isEmpty) &&
        (message.mediaUrl != null && message.mediaUrl!.isNotEmpty);
    final reactionCounts = message.reactionCounts;

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
              if (message.isForwarded) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forward_rounded,
                        size: 13,
                        color: secondaryText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Encaminhada',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              hasLegacyUrl
                  ? Image.network(
                      message.mediaUrl!,
                      width: 148,
                      height: 148,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 148,
                        height: 148,
                        child: Icon(Icons.sticky_note_2_rounded, size: 54),
                      ),
                    )
                  : ZapiStickerImage(
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
                        status: visibleStatus,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
              if (reactionCounts.isNotEmpty) ...[
                const SizedBox(height: 3),
                _ReactionsStrip(
                  counts: reactionCounts,
                  myReaction: message.reactionFor(currentUid),
                  isDark: isDark,
                  onTap: onReactionTap,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBubbleContent extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<_ImageBubbleContent> createState() =>
      _ImageBubbleContentState();
}

class _ImageBubbleContentState extends ConsumerState<_ImageBubbleContent> {
  static final Map<String, Uint8List> _thumbMemoryCache = {};
  File? _resolvedFullFile;
  bool _requestedFull = false;

  @override
  void initState() {
    super.initState();
    _resolveFullQuality();
  }

  @override
  void didUpdateWidget(covariant _ImageBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaId != widget.message.mediaId ||
        oldWidget.message.isUploading != widget.message.isUploading) {
      _requestedFull = false;
      _resolveFullQuality();
    }
  }

  Future<void> _resolveFullQuality() async {
    final msg = widget.message;
    if (_requestedFull ||
        msg.isUploading ||
        msg.uploadFailed ||
        msg.chatId.isEmpty ||
        msg.mediaId == null ||
        msg.mediaId!.isEmpty) {
      return;
    }

    final localPath = msg.localMediaPath;
    if (localPath != null && File(localPath).existsSync()) {
      return;
    }

    _requestedFull = true;
    try {
      final file = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
            chatId: msg.chatId,
            mediaId: msg.mediaId!,
            mimeType: msg.mimeType ?? 'image/jpeg',
          );
      if (mounted && file != null && await file.exists()) {
        setState(() => _resolvedFullFile = file);
      }
    } catch (_) {}
  }

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
    final message = widget.message;
    final aspect = (message.width != null &&
            message.height != null &&
            message.height! > 0)
        ? (message.width! / message.height!).clamp(0.62, 1.5)
        : 1.0;

    final fullLocalPath = message.localMediaPath;
    final hasFullLocal =
        fullLocalPath != null && File(fullLocalPath).existsSync();
    final fallbackLocalPath = message.localThumbnailPath;
    final hasThumbLocal =
        fallbackLocalPath != null && File(fallbackLocalPath).existsSync();
    final thumbBytes = _decodeThumb(message.thumbnailBase64);
    final legacyNetworkUrl = message.thumbnailUrl ?? message.mediaUrl ?? '';

    Widget imageWidget;
    if (hasFullLocal) {
      imageWidget = Image.file(
        File(fullLocalPath),
        key: ValueKey('full_$fullLocalPath'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else if (_resolvedFullFile != null) {
      imageWidget = Image.file(
        _resolvedFullFile!,
        key: ValueKey('cached_${_resolvedFullFile!.path}'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else if (hasThumbLocal) {
      imageWidget = Image.file(
        File(fallbackLocalPath),
        key: ValueKey('local_thumb_$fallbackLocalPath'),
        fit: BoxFit.cover,
      );
    } else if (thumbBytes != null) {
      imageWidget = Image.memory(
        thumbBytes,
        key: const ValueKey('thumb_mem'),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black12,
          child: Center(child: Icon(Icons.broken_image_rounded, size: 36)),
        ),
      );
    } else if (legacyNetworkUrl.isNotEmpty) {
      imageWidget = Image.network(
        legacyNetworkUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Colors.black12,
          child: Center(child: Icon(Icons.broken_image_rounded, size: 36)),
        ),
      );
    } else {
      imageWidget = const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.photo_rounded, size: 36)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: message.isUploading || message.uploadFailed
              ? null
              : widget.onImageTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: SizedBox.expand(child: imageWidget),
                  ),
                  if (message.isUploading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Center(
                        child: GestureDetector(
                          onTap: widget.onCancelUpload,
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
                              onPressed: widget.onRetryUpload,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.emerald,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Tentar de novo'),
                            ),
                            if (widget.onCancelUpload != null) ...[
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: widget.onCancelUpload,
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
                color: widget.textColor,
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
          ZapiToast.showError(
            context,
            'Áudio indisponível ou apagado.',
            bottomOffset: 80,
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
        ZapiToast.showError(
          context,
          'Não foi possível baixar este áudio.',
          bottomOffset: 80,
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
    ref.listen<String?>(
      audioPlaybackProvider.select((s) => s.errorMessage),
      (_, nextError) {
        if (!mounted || nextError == null) return;
        final currentActive = ref.read(audioPlaybackProvider).activeMessageId;
        if (currentActive == message.id) {
          ZapiToast.showError(context, nextError, bottomOffset: 80);
          ref.read(audioPlaybackProvider.notifier).clearError();
        }
      },
    );
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
                        void seekAt(double dx) {
                          if (!isActive ||
                              totalDuration <= Duration.zero ||
                              constraints.maxWidth <= 0) {
                            return;
                          }
                          final fraction =
                              (dx / constraints.maxWidth).clamp(0.0, 1.0);
                          final target = Duration(
                            milliseconds:
                                (totalDuration.inMilliseconds * fraction)
                                    .round(),
                          );
                          ref
                              .read(audioPlaybackProvider.notifier)
                              .seek(message.id, target);
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: isActive && totalDuration > Duration.zero
                              ? (details) => seekAt(details.localPosition.dx)
                              : null,
                          onHorizontalDragStart:
                              isActive && totalDuration > Duration.zero
                                  ? (details) => seekAt(details.localPosition.dx)
                                  : null,
                          onHorizontalDragUpdate:
                              isActive && totalDuration > Duration.zero
                                  ? (details) => seekAt(details.localPosition.dx)
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

class _VideoBubbleContent extends StatelessWidget {
  const _VideoBubbleContent({
    required this.message,
    required this.textColor,
    this.onVideoTap,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  final ChatMessage message;
  final Color textColor;
  final VoidCallback? onVideoTap;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final durationLabel = message.durationMs != null && message.durationMs! > 0
        ? DateFormatter.formatDuration(
            Duration(milliseconds: message.durationMs!),
          )
        : 'Vídeo';
    final sizeLabel = message.sizeBytes != null && message.sizeBytes! > 0
        ? '${(message.sizeBytes! / 1024).ceil()} KB'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap:
              message.isUploading || message.uploadFailed ? null : onVideoTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF102A24),
                      Color(0xFF0B141A),
                    ],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: message.isUploading
                          ? GestureDetector(
                              onTap: onCancelUpload,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
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
                            )
                          : message.uploadFailed
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: onRetryUpload,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.emerald,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Tentar de novo'),
                                    ),
                                    if (onCancelUpload != null)
                                      TextButton(
                                        onPressed: onCancelUpload,
                                        child: const Text(
                                          'Cancelar',
                                          style:
                                              TextStyle(color: Colors.white70),
                                        ),
                                      ),
                                  ],
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.56),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.videocam_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sizeLabel != null
                                  ? '$durationLabel · $sizeLabel'
                                  : durationLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
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

class _FileBubbleContent extends ConsumerStatefulWidget {
  const _FileBubbleContent({
    required this.message,
    required this.isMine,
    required this.isDark,
    required this.textColor,
    required this.secondaryText,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isDark;
  final Color textColor;
  final Color secondaryText;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;

  @override
  ConsumerState<_FileBubbleContent> createState() => _FileBubbleContentState();
}

class _FileBubbleContentState extends ConsumerState<_FileBubbleContent> {
  bool _loadingFile = false;

  String _resolveDisplayName() {
    final raw = (widget.message.fileName ?? '').trim();
    return raw.isNotEmpty ? raw : 'Arquivo';
  }

  String _resolveExt(String fileName) {
    final ext = p.extension(fileName).replaceFirst('.', '').trim();
    if (ext.isNotEmpty) return ext.toUpperCase();
    final mime = widget.message.mimeType ?? '';
    if (mime == 'application/pdf') return 'PDF';
    if (mime.startsWith('audio/')) return 'ÁUDIO';
    if (mime == 'text/plain') return 'TXT';
    if (mime == 'application/zip') return 'ZIP';
    return 'ARQUIVO';
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'MP3':
      case 'M4A':
      case 'OGG':
      case 'WAV':
      case 'ÁUDIO':
        return Icons.audio_file_rounded;
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return Icons.folder_zip_rounded;
      case 'TXT':
      case 'DOC':
      case 'DOCX':
      case 'ODT':
        return Icons.description_rounded;
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return Icons.table_chart_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).ceil()} KB';
  }

  Future<File?> _resolveFile() async {
    final msg = widget.message;
    if (msg.localMediaPath != null && File(msg.localMediaPath!).existsSync()) {
      return File(msg.localMediaPath!);
    }
    if (msg.chatId.isEmpty || msg.mediaId == null || msg.mediaId!.isEmpty) {
      return null;
    }
    return ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
          chatId: msg.chatId,
          mediaId: msg.mediaId!,
          mimeType: msg.mimeType,
          fileName: msg.fileName,
        );
  }

  Future<void> _handleOpen({required bool share}) async {
    if (_loadingFile ||
        widget.message.isUploading ||
        widget.message.uploadFailed) {
      return;
    }
    setState(() => _loadingFile = true);
    try {
      final file = await _resolveFile();
      if (!mounted) return;
      if (file == null || !await file.exists()) {
        ZapiToast.showError(
          context,
          'Arquivo indisponível ou apagado.',
          bottomOffset: 80,
        );
        return;
      }

      if (share) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: _resolveDisplayName(),
        );
      } else {
        final result = await OpenFilex.open(
          file.path,
          type: widget.message.mimeType,
        );
        if (!mounted) return;
        if (result.type != ResultType.done) {
          ZapiToast.showError(
            context,
            'Nenhum aplicativo encontrado para abrir este arquivo.',
            bottomOffset: 80,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível abrir este arquivo.',
        bottomOffset: 80,
      );
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final displayName = _resolveDisplayName();
    final ext = _resolveExt(displayName);
    final sizeText = _formatSize(message.sizeBytes);
    final meta = sizeText.isEmpty ? ext : '$ext · $sizeText';
    final cardBg = widget.isMine
        ? (widget.isDark
            ? Colors.black.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.05))
        : (widget.isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt);

    return Container(
      width: 244,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _handleOpen(share: false),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconForExt(ext),
                color: AppColors.emerald,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: widget.textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.uploadFailed ? 'Falha no envio' : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: message.uploadFailed
                          ? Theme.of(context).colorScheme.error
                          : widget.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (message.isUploading)
              GestureDetector(
                onTap: widget.onCancelUpload,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: message.uploadProgress != null &&
                                message.uploadProgress! > 0
                            ? message.uploadProgress
                            : null,
                        strokeWidth: 2.5,
                        color: AppColors.emerald,
                      ),
                      Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: widget.textColor,
                      ),
                    ],
                  ),
                ),
              )
            else if (message.uploadFailed)
              IconButton(
                tooltip: 'Tentar enviar novamente',
                onPressed: widget.onRetryUpload,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            else if (_loadingFile)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.emerald,
                ),
              )
            else
              IconButton(
                tooltip: 'Salvar ou compartilhar',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleOpen(share: true),
                icon: Icon(
                  Icons.save_alt_rounded,
                  color: widget.secondaryText,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

