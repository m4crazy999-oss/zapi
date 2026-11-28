import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/audio_playback_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';

class ChatAudioMiniBar extends ConsumerWidget {
  const ChatAudioMiniBar({
    super.key,
    required this.chatId,
  });

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(audioPlaybackProvider);
    final activeId = playback.activeMessageId;
    if (activeId == null || playback.activeChatId != chatId) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final totalMs = playback.duration.inMilliseconds;
    final posMs = playback.position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0);
    final speedLabel = playback.speed == 1.0
        ? '1x'
        : (playback.speed == 1.5 ? '1.5x' : '2x');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      child: Row(
        children: [
          IconButton(
            tooltip: playback.isPlaying ? 'Pausar áudio' : 'Retomar áudio',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              if (playback.isPlaying) {
                ref.read(audioPlaybackProvider.notifier).pause();
              } else {
                ref.read(audioPlaybackProvider.notifier).resumeCurrent();
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: primaryColor.withValues(alpha: 0.14),
              foregroundColor: primaryColor,
            ),
            icon: playback.isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                : Icon(
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (playback.activeSenderName ?? '').isNotEmpty
                            ? 'Áudio · ${playback.activeSenderName}'
                            : 'Reproduzindo áudio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      totalMs > 0
                          ? '${DateFormatter.formatDuration(playback.position)} / ${DateFormatter.formatDuration(playback.duration)}'
                          : DateFormatter.formatDuration(playback.position),
                      style: TextStyle(
                        fontSize: 11,
                        color: secondaryText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                if (totalMs > 0)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5.5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 11,
                      ),
                    ),
                    child: Slider(
                      value: posMs.toDouble(),
                      min: 0,
                      max: totalMs.toDouble(),
                      activeColor: primaryColor,
                      inactiveColor: secondaryText.withValues(alpha: 0.25),
                      onChanged: (v) {
                        ref.read(audioPlaybackProvider.notifier).seek(
                              activeId,
                              Duration(milliseconds: v.round()),
                            );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => ref.read(audioPlaybackProvider.notifier).cycleSpeed(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                speedLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: primaryColor,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fechar player',
            visualDensity: VisualDensity.compact,
            onPressed: () => ref.read(audioPlaybackProvider.notifier).stop(),
            icon: Icon(Icons.close_rounded, size: 19, color: secondaryText),
          ),
        ],
      ),
    );
  }
}
