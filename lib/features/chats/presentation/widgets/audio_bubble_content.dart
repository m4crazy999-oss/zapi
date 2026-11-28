import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../domain/chat_message.dart';

class AudioBubbleContent extends ConsumerStatefulWidget {
  const AudioBubbleContent({
    super.key,
    required this.message,
    required this.isMine,
    required this.currentUid,
    required this.peerUid,
    required this.senderLabel,
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
  final String senderLabel;
  final bool isDark;
  final Color textColor;
  final Color secondaryText;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;
  final VoidCallback? onAudioStarted;

  @override
  ConsumerState<AudioBubbleContent> createState() => _AudioBubbleContentState();
}

class _AudioBubbleContentState extends ConsumerState<AudioBubbleContent> {
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
    final label = widget.isMine ? 'Você' : widget.senderLabel;

    final hasLocal = message.localMediaPath != null &&
        File(message.localMediaPath!).existsSync();

    if (hasLocal) {
      await ref.read(audioPlaybackProvider.notifier).togglePlay(
            messageId: message.id,
            urlOrPath: message.localMediaPath!,
            isLocalFile: true,
            chatId: message.chatId,
            senderName: label,
            fallbackDuration: totalDuration,
            onStarted: widget.onAudioStarted,
          );
      return;
    }

    if (message.chatId.isNotEmpty &&
        message.mediaId != null &&
        message.mediaId!.isNotEmpty) {
      final playback = ref.read(audioPlaybackProvider);
      if (playback.activeMessageId == message.id && playback.isPlaying) {
        await ref.read(audioPlaybackProvider.notifier).pause();
        return;
      }
      setState(() => _fetchingAudio = true);
      File? cached;
      try {
        cached = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
              chatId: message.chatId,
              mediaId: message.mediaId!,
              mimeType: message.mimeType ?? 'audio/mp4',
            );
      } catch (_) {
        if (mounted) {
          setState(() => _fetchingAudio = false);
          ZapiToast.showError(
            context,
            'Não foi possível baixar este áudio.',
            bottomOffset: 80,
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _fetchingAudio = false);
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
            chatId: message.chatId,
            senderName: label,
            fallbackDuration: totalDuration,
            onStarted: widget.onAudioStarted,
          );
      return;
    }

    final legacyUrl = message.mediaUrl ?? '';
    if (legacyUrl.isEmpty) return;
    await ref.read(audioPlaybackProvider.notifier).togglePlay(
          messageId: message.id,
          urlOrPath: legacyUrl,
          isLocalFile: false,
          chatId: message.chatId,
          senderName: label,
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
