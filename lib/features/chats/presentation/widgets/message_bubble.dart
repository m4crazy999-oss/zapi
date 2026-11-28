import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../stickers/presentation/widgets/zapi_sticker_image.dart';
import '../../domain/chat_message.dart';
import 'audio_bubble_content.dart';
import 'media_bubble_contents.dart';

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
    this.senderLabel = 'Contato',
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
  final String senderLabel;
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
    final messageFontSize =
        ref.watch(chatPreferencesProvider.select((s) => s.messageFontSize));
    final accentColor = Theme.of(context).colorScheme.primary;

    if (message.isSticker && !message.deletedForEveryone) {
      return _StickerBubble(
        message: message,
        isMine: isMine,
        currentUid: currentUid,
        isDark: isDark,
        accentColor: accentColor,
        visibleStatus: _visibleStatus(),
        onLongPress: onLongPress,
        onReactionTap: onReactionTap,
      );
    }

    final bubbleColor = isMine
        ? (isDark
            ? accentColor.withValues(alpha: 0.24)
            : Color.lerp(const Color(0xFFE7FBEF), accentColor, 0.14)!)
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
                            border: Border(
                              left: BorderSide(
                                color: accentColor,
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
                                  color: accentColor,
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
                                fontSize: (messageFontSize - 1).clamp(12.5, 16),
                                fontStyle: FontStyle.italic,
                                color: secondaryText,
                              ),
                            ),
                          ],
                        )
                      else if (message.isImage)
                        ImageBubbleContent(
                          message: message,
                          textColor: textColor,
                          fontSize: messageFontSize,
                          onImageTap: onImageTap,
                          onCancelUpload: onCancelUpload,
                          onRetryUpload: onRetryUpload,
                        )
                      else if (message.isVideo)
                        VideoBubbleContent(
                          message: message,
                          textColor: textColor,
                          fontSize: messageFontSize,
                          onVideoTap: onVideoTap,
                          onCancelUpload: onCancelUpload,
                          onRetryUpload: onRetryUpload,
                        )
                      else if (message.isFile)
                        FileBubbleContent(
                          message: message,
                          isMine: isMine,
                          isDark: isDark,
                          textColor: textColor,
                          secondaryText: secondaryText,
                          onCancelUpload: onCancelUpload,
                          onRetryUpload: onRetryUpload,
                        )
                      else if (message.isAudio)
                        AudioBubbleContent(
                          message: message,
                          isMine: isMine,
                          currentUid: currentUid,
                          peerUid: peerUid,
                          senderLabel: senderLabel,
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
                            fontSize: messageFontSize,
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
                    accentColor: accentColor,
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
    required this.accentColor,
    this.onTap,
  });

  final Map<String, int> counts;
  final String? myReaction;
  final bool isDark;
  final Color accentColor;
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
                  ? accentColor.withValues(alpha: isDark ? 0.28 : 0.16)
                  : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? accentColor
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
                          ? accentColor
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
    required this.accentColor,
    required this.visibleStatus,
    required this.onLongPress,
    this.onReactionTap,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUid;
  final bool isDark;
  final Color accentColor;
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
                  accentColor: accentColor,
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
