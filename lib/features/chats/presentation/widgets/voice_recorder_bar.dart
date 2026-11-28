import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/permission_helper.dart';

class VoiceRecorderController {
  VoiceRecorderController({
    required this.onCompleted,
    required this.onStateChanged,
    required this.onFeedbackMessage,
    this.onBeforeRecordStart,
  });

  final void Function(String filePath, int durationMs) onCompleted;
  final VoidCallback onStateChanged;
  final ValueChanged<String> onFeedbackMessage;
  final Future<void> Function()? onBeforeRecordStart;

  final AudioRecorder _recorder = AudioRecorder();
  static const _uuid = Uuid();
  static const int _barCount = 18;

  bool isHoldingMic = false;
  bool isRecording = false;
  bool isPaused = false;
  bool isLocked = false;
  bool isCanceling = false;
  bool isPreviewing = false;
  bool isPreviewPlaying = false;
  Duration elapsed = Duration.zero;
  Duration previewPosition = Duration.zero;
  Duration previewDuration = Duration.zero;
  double dragDx = 0;
  double dragDy = 0;
  final List<double> liveAmplitudes =
      List<double>.filled(_barCount, 0.14, growable: true);

  Timer? _tickTimer;
  Timer? _ampTimer;
  DateTime? _startedAt;
  Duration _accumulatedBeforePause = Duration.zero;
  String? _currentPath;
  String? _recordedPreviewPath;
  int _previewDurationMs = 0;
  Offset? _pointerStart;
  bool _starting = false;
  bool _pointerReleasedDuringStart = false;
  Future<void>? _stopInFlight;

  AudioPlayer? _previewPlayer;
  StreamSubscription<Duration>? _previewPosSub;
  StreamSubscription<PlayerState>? _previewStateSub;

  bool get isActive => isRecording || isPreviewing;
  double get lockProgress =>
      isRecording && !isLocked ? (-dragDy / 72.0).clamp(0.0, 1.0) : 0.0;
  double get cancelProgress =>
      isRecording && !isLocked ? (-dragDx / 95.0).clamp(0.0, 1.0) : 0.0;

  Future<void> handlePointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) async {
    if (isRecording || isPreviewing || _starting) return;
    _starting = true;
    _pointerReleasedDuringStart = false;
    _pointerStart = event.position;
    isHoldingMic = true;
    unawaited(HapticFeedback.selectionClick());
    onStateChanged();

    try {
      final pendingStop = _stopInFlight;
      if (pendingStop != null) {
        await pendingStop.catchError((_) {});
      }
      if (_pointerReleasedDuringStart) return;

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        if (context.mounted) {
          await PermissionHelper.requestMicrophone(context);
        }
        return;
      }

      if (!await _recorder.hasPermission()) {
        return;
      }
      if (_pointerReleasedDuringStart) return;

      if (onBeforeRecordStart != null) {
        await onBeforeRecordStart!().catchError((_) {});
      }
      if (_pointerReleasedDuringStart) return;

      final dir = await getTemporaryDirectory();
      final outDir = Directory(p.join(dir.path, 'zapi_voice'));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final filePath = p.join(outDir.path, 'voice_${_uuid.v4()}.m4a');
      await _startRecorderWithSafeConfig(filePath);

      if (_pointerReleasedDuringStart) {
        await _recorder.cancel().catchError((_) {});
        final stale = File(filePath);
        if (await stale.exists()) {
          await stale.delete().catchError((_) => stale);
        }
        return;
      }

      _currentPath = filePath;
      _startedAt = DateTime.now();
      _accumulatedBeforePause = Duration.zero;
      isRecording = true;
      isPaused = false;
      isLocked = false;
      isCanceling = false;
      isPreviewing = false;
      elapsed = Duration.zero;
      dragDx = 0;
      dragDy = 0;
      liveAmplitudes
        ..clear()
        ..addAll(List<double>.filled(_barCount, 0.14));

      await HapticFeedback.mediumImpact();
      _startTimers();
      onStateChanged();
    } catch (_) {
      onFeedbackMessage('Não foi possível acessar o microfone agora.');
      await cancelRecording();
    } finally {
      _starting = false;
      isHoldingMic = false;
      onStateChanged();
    }
  }

  Future<void> _startRecorderWithSafeConfig(String filePath) async {
    const primaryConfig = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: AppConstants.audioBitRate,
      sampleRate: AppConstants.audioSampleRate,
      numChannels: 1,
      noiseSuppress: true,
      echoCancel: false,
      autoGain: false,
    );

    try {
      await _recorder.start(primaryConfig, path: filePath);
    } catch (_) {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: AppConstants.audioBitRate,
          sampleRate: AppConstants.audioSampleRate,
          numChannels: 1,
          noiseSuppress: false,
          echoCancel: false,
          autoGain: false,
        ),
        path: filePath,
      );
    }
  }

  void handlePointerMove(PointerMoveEvent event) {
    if (!isRecording || isLocked || _pointerStart == null) return;
    final dx = event.position.dx - _pointerStart!.dx;
    final dy = event.position.dy - _pointerStart!.dy;

    final nextDx = dx < 0 && dy > -36 ? dx.clamp(-140.0, 0.0) : 0.0;
    final nextDy = dy < 0 && dx > -42 ? dy.clamp(-110.0, 0.0) : 0.0;
    dragDx = nextDx;
    dragDy = nextDy;

    final nextCanceling = nextDx < -95;
    if (nextCanceling != isCanceling) {
      isCanceling = nextCanceling;
      if (isCanceling) {
        unawaited(HapticFeedback.mediumImpact());
      }
    }

    if (nextDy < -68) {
      isLocked = true;
      isCanceling = false;
      dragDx = 0;
      dragDy = 0;
      unawaited(HapticFeedback.mediumImpact());
    }
    onStateChanged();
  }

  Future<void> handlePointerUpOrCancel() async {
    isHoldingMic = false;
    if (_starting && !isRecording) {
      _pointerReleasedDuringStart = true;
      onStateChanged();
      return;
    }
    if (!isRecording || isLocked) {
      onStateChanged();
      return;
    }

    if (isCanceling) {
      await cancelRecording();
      return;
    }

    final durationMs = _currentDurationMs();
    if (durationMs < 450) {
      await cancelRecording();
      return;
    }

    await finishAndSend();
  }

  Future<void> pauseRecording() async {
    if (!isRecording || isPaused || _stopInFlight != null) return;
    try {
      _stopTimers();
      final totalMs = _currentDurationMs();
      _accumulatedBeforePause = Duration(milliseconds: totalMs);
      elapsed = _accumulatedBeforePause;
      _startedAt = null;
      isLocked = true;
      await _recorder.pause();
      isPaused = true;
      await HapticFeedback.selectionClick();
      onStateChanged();
    } catch (_) {
      onFeedbackMessage('Não foi possível pausar este áudio agora.');
    }
  }

  Future<void> resumeRecording() async {
    if (!isRecording || !isPaused || _stopInFlight != null) return;
    try {
      if (onBeforeRecordStart != null) {
        await onBeforeRecordStart!().catchError((_) {});
      }
      await _recorder.resume();
      _startedAt = DateTime.now();
      isPaused = false;
      _startTimers();
      await HapticFeedback.lightImpact();
      onStateChanged();
    } catch (_) {
      onFeedbackMessage('Não foi possível continuar a gravação.');
    }
  }

  Future<void> togglePauseResume() async {
    if (isPaused) {
      await resumeRecording();
    } else {
      await pauseRecording();
    }
  }

  Future<void> enterPreviewMode() async {
    if (!isRecording || _stopInFlight != null) return;
    final completer = Completer<void>();
    _stopInFlight = completer.future;

    try {
      _stopTimers();
      final durationMs = _currentDurationMs()
          .clamp(450, AppConstants.maxAudioDuration.inMilliseconds);
      final recordedPath = await _recorder.stop() ?? _currentPath;
      if (recordedPath == null || !await File(recordedPath).exists()) {
        _resetState();
        onStateChanged();
        return;
      }

      isRecording = false;
      isPaused = false;
      isLocked = false;
      isCanceling = false;
      isPreviewing = true;
      isPreviewPlaying = false;
      _recordedPreviewPath = recordedPath;
      _previewDurationMs = durationMs;
      previewDuration = Duration(milliseconds: durationMs);
      previewPosition = Duration.zero;
      _startedAt = null;
      _currentPath = null;
      onStateChanged();
    } catch (_) {
      onFeedbackMessage('Não foi possível preparar a prévia do áudio.');
      await cancelRecording();
    } finally {
      _stopInFlight = null;
      completer.complete();
    }
  }

  Future<void> togglePreviewPlay() async {
    final path = _recordedPreviewPath;
    if (!isPreviewing || path == null) return;

    try {
      final player = _previewPlayer;
      if (player != null && (player.playing || isPreviewPlaying)) {
        await player.pause();
        isPreviewPlaying = false;
        onStateChanged();
        return;
      }

      if (onBeforeRecordStart != null) {
        await onBeforeRecordStart!().catchError((_) {});
      }

      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        ),
      );
      await session.setActive(true);

      if (_previewPlayer == null) {
        final pInstance = AudioPlayer();
        _previewPlayer = pInstance;
        await pInstance.setFilePath(path);
        final actualDur = pInstance.duration;
        if (actualDur != null && actualDur > Duration.zero) {
          previewDuration = actualDur;
          _previewDurationMs = actualDur.inMilliseconds;
        }
        _previewPosSub = pInstance.positionStream.listen((pos) {
          if (!isPreviewing) return;
          previewPosition = pos;
          onStateChanged();
        });
        _previewStateSub = pInstance.playerStateStream.listen((ps) async {
          if (!isPreviewing) return;
          if (ps.processingState == ProcessingState.completed) {
            await pInstance.pause();
            await pInstance.seek(Duration.zero);
            isPreviewPlaying = false;
            previewPosition = Duration.zero;
            onStateChanged();
          } else {
            isPreviewPlaying = ps.playing;
            onStateChanged();
          }
        });
      }

      isPreviewPlaying = true;
      onStateChanged();
      await _previewPlayer!.setVolume(1.0);
      unawaited(
        _previewPlayer!.play().catchError((_) {
          isPreviewPlaying = false;
          onStateChanged();
          onFeedbackMessage('Não foi possível reproduzir a prévia.');
        }),
      );
    } catch (_) {
      isPreviewPlaying = false;
      onStateChanged();
      onFeedbackMessage('Não foi possível reproduzir a prévia.');
    }
  }

  Future<void> seekPreview(Duration target) async {
    final player = _previewPlayer;
    if (!isPreviewing || player == null) return;
    final maxMs = previewDuration.inMilliseconds;
    final clamped = maxMs > 0
        ? Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs))
        : target;
    previewPosition = clamped;
    onStateChanged();
    await player.seek(clamped);
  }

  Future<void> sendPreviewed() async {
    if (!isPreviewing) return;
    final path = _recordedPreviewPath;
    final durationMs = _previewDurationMs;
    await _disposePreviewPlayer();
    _resetState();
    onStateChanged();

    if (path != null) {
      final file = File(path);
      if (await file.exists() && await file.length() > 512) {
        onCompleted(path, durationMs.clamp(450, AppConstants.maxAudioDuration.inMilliseconds));
      } else if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
  }

  Future<void> discardPreview() async {
    final path = _recordedPreviewPath;
    await _disposePreviewPlayer();
    _resetState();
    onStateChanged();
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        await f.delete().catchError((_) => f);
      }
    }
  }

  Future<void> _disposePreviewPlayer() async {
    await _previewPosSub?.cancel();
    await _previewStateSub?.cancel();
    _previewPosSub = null;
    _previewStateSub = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    if (player != null) {
      await player.stop().catchError((_) {});
      await player.dispose().catchError((_) {});
    }
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  Future<void> finishAndSend() async {
    if (!isRecording) return;
    if (_stopInFlight != null) {
      await _stopInFlight;
      return;
    }

    final completer = Completer<void>();
    _stopInFlight = completer.future;

    try {
      _stopTimers();
      final durationMs = _currentDurationMs()
          .clamp(450, AppConstants.maxAudioDuration.inMilliseconds);
      final recordedPath = await _recorder.stop() ?? _currentPath;

      _resetState();
      onStateChanged();

      if (recordedPath != null) {
        final file = File(recordedPath);
        if (await file.exists()) {
          final size = await file.length();
          if (size > 512) {
            onCompleted(recordedPath, durationMs);
          } else {
            await file.delete().catchError((_) => file);
          }
        }
      }
    } catch (_) {
      _resetState();
      onStateChanged();
    } finally {
      _stopInFlight = null;
      completer.complete();
    }
  }

  Future<void> cancelRecording() async {
    if (_stopInFlight != null) {
      await _stopInFlight;
      return;
    }

    final completer = Completer<void>();
    _stopInFlight = completer.future;

    try {
      _stopTimers();
      final pathToDelete = _currentPath;
      try {
        await _recorder.cancel();
      } catch (_) {}

      if (pathToDelete != null) {
        final f = File(pathToDelete);
        if (await f.exists()) {
          await f.delete().catchError((_) => f);
        }
      }

      _resetState();
      onStateChanged();
    } finally {
      _stopInFlight = null;
      completer.complete();
    }
  }

  void _startTimers() {
    _tickTimer?.cancel();
    _ampTimer?.cancel();

    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!isRecording || isPaused || _startedAt == null) return;
      final total = _accumulatedBeforePause +
          DateTime.now().difference(_startedAt!);
      elapsed = total;
      if (total >= AppConstants.maxAudioDuration) {
        onFeedbackMessage('Limite de 3 minutos atingido. Enviando áudio...');
        await finishAndSend();
        return;
      }
      onStateChanged();
    });

    _ampTimer = Timer.periodic(const Duration(milliseconds: 65), (_) async {
      if (!isRecording || isPaused) return;
      try {
        final amp = await _recorder.getAmplitude();
        final db = amp.current.isFinite ? amp.current : -60.0;
        final rawNorm = ((db + 45.0) / 42.0).clamp(0.10, 1.0);
        final prev = liveAmplitudes.isNotEmpty ? liveAmplitudes.last : 0.14;
        final smoothed = (prev * 0.25 + rawNorm * 0.75).clamp(0.10, 1.0);

        if (liveAmplitudes.length >= _barCount) {
          liveAmplitudes.removeAt(0);
        }
        liveAmplitudes.add(smoothed);
        onStateChanged();
      } catch (_) {}
    });
  }

  void _stopTimers() {
    _tickTimer?.cancel();
    _ampTimer?.cancel();
    _tickTimer = null;
    _ampTimer = null;
  }

  int _currentDurationMs() {
    if (isPaused || _startedAt == null) {
      return _accumulatedBeforePause.inMilliseconds;
    }
    return _accumulatedBeforePause.inMilliseconds +
        DateTime.now().difference(_startedAt!).inMilliseconds;
  }

  void _resetState() {
    isHoldingMic = false;
    isRecording = false;
    isPaused = false;
    isLocked = false;
    isCanceling = false;
    isPreviewing = false;
    isPreviewPlaying = false;
    elapsed = Duration.zero;
    previewPosition = Duration.zero;
    previewDuration = Duration.zero;
    dragDx = 0;
    dragDy = 0;
    _startedAt = null;
    _accumulatedBeforePause = Duration.zero;
    _currentPath = null;
    _recordedPreviewPath = null;
    _previewDurationMs = 0;
    _pointerStart = null;
  }

  Future<void> dispose() async {
    _stopTimers();
    await _disposePreviewPlayer();
    final previewPath = _recordedPreviewPath;
    if (previewPath != null) {
      final f = File(previewPath);
      if (await f.exists()) {
        await f.delete().catchError((_) => f);
      }
    }
    if (isRecording) {
      await _recorder.cancel().catchError((_) {});
    }
    await _recorder.dispose();
  }
}

class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.controller,
  });

  final VoiceRecorderController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (controller.isPreviewing) {
      final totalMs = controller.previewDuration.inMilliseconds;
      final posMs = controller.previewPosition.inMilliseconds
          .clamp(0, totalMs > 0 ? totalMs : 0);
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: controller.discardPreview,
              tooltip: 'Descartar áudio',
              icon: Icon(
                Icons.delete_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            IconButton(
              onPressed: controller.togglePreviewPlay,
              tooltip: controller.isPreviewPlaying ? 'Pausar' : 'Ouvir',
              style: IconButton.styleFrom(
                backgroundColor: primaryColor.withValues(alpha: 0.14),
                foregroundColor: primaryColor,
              ),
              icon: Icon(
                controller.isPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.8,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: totalMs > 0 ? posMs.toDouble() : 0,
                      min: 0,
                      max: totalMs > 0 ? totalMs.toDouble() : 1,
                      activeColor: primaryColor,
                      inactiveColor: secondaryText.withValues(alpha: 0.28),
                      onChanged: totalMs > 0
                          ? (v) => controller.seekPreview(
                                Duration(milliseconds: v.round()),
                              )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              controller.isPreviewPlaying || posMs > 0
                  ? DateFormatter.formatDuration(controller.previewPosition)
                  : DateFormatter.formatDuration(controller.previewDuration),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: controller.sendPreviewed,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      );
    }

    if (controller.isLocked) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: controller.cancelRecording,
              tooltip: 'Cancelar áudio',
              icon: Icon(
                Icons.delete_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            if (controller.isPaused)
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
              )
            else
              const _PulsingMicDot(),
            const SizedBox(width: 8),
            Text(
              DateFormatter.formatDuration(controller.elapsed),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Opacity(
                opacity: controller.isPaused ? 0.45 : 1.0,
                child: _LiveWaveform(amplitudes: controller.liveAmplitudes),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: controller.enterPreviewMode,
              tooltip: 'Ouvir antes de enviar',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: isDark
                    ? AppColors.darkSurfaceAlt
                    : AppColors.lightSurfaceAlt,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              icon: const Icon(Icons.headphones_rounded, size: 19),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: controller.togglePauseResume,
              tooltip: controller.isPaused
                  ? 'Continuar gravação'
                  : 'Pausar gravação',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: controller.isPaused
                    ? primaryColor.withValues(alpha: 0.16)
                    : (isDark
                        ? AppColors.darkSurfaceAlt
                        : AppColors.lightSurfaceAlt),
                foregroundColor: controller.isPaused
                    ? primaryColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
              icon: Icon(
                controller.isPaused ? Icons.mic_rounded : Icons.pause_rounded,
                size: 20,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: controller.finishAndSend,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      );
    }

    final lockProgress = controller.lockProgress;
    final cancelProgress = controller.cancelProgress;
    final activePillBg = Color.lerp(
      isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      Theme.of(context).colorScheme.error.withValues(alpha: 0.16),
      cancelProgress,
    )!;
    final micBg = Color.lerp(
      primaryColor,
      Theme.of(context).colorScheme.error,
      cancelProgress,
    )!;
    final micOffset = Offset(
      controller.dragDx * 0.35,
      controller.dragDy * 0.72,
    );
    final lockTrackOpacity = (1.0 - cancelProgress * 1.6).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: activePillBg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const _PulsingMicDot(),
                      const SizedBox(width: 8),
                      Text(
                        DateFormatter.formatDuration(controller.elapsed),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: controller.isCanceling
                            ? Center(
                                child: Text(
                                  'Solte para cancelar',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : Opacity(
                                opacity: (1.0 - cancelProgress * 0.45)
                                    .clamp(0.25, 1.0),
                                child: _LiveWaveform(
                                  amplitudes: controller.liveAmplitudes,
                                ),
                              ),
                      ),
                      if (!controller.isCanceling) ...[
                        const SizedBox(width: 6),
                        Opacity(
                          opacity:
                              (1.0 - lockProgress * 1.4).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(controller.dragDx * 0.42, 0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chevron_left_rounded,
                                  size: 16,
                                  color: secondaryText,
                                ),
                                Text(
                                  'Deslize',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: secondaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 64),
            ],
          ),
          if (lockTrackOpacity > 0.02)
            Positioned(
              right: 5,
              bottom: 66 + (lockProgress * 6),
              child: IgnorePointer(
                child: Opacity(
                  opacity: lockTrackOpacity,
                  child: _FloatingLockTrack(
                    progress: lockProgress,
                    isDark: isDark,
                    accentColor: primaryColor,
                    secondaryText: secondaryText,
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: micOffset,
            child: _PulsingMicButton(
              color: micBg,
              isCanceling: controller.isCanceling,
              scale: controller.isCanceling
                  ? 1.04
                  : (1.10 + lockProgress * 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingLockTrack extends StatefulWidget {
  const _FloatingLockTrack({
    required this.progress,
    required this.isDark,
    required this.accentColor,
    required this.secondaryText,
  });

  final double progress;
  final bool isDark;
  final Color accentColor;
  final Color secondaryText;

  @override
  State<_FloatingLockTrack> createState() => _FloatingLockTrackState();
}

class _FloatingLockTrackState extends State<_FloatingLockTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chevronController;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.clamp(0.0, 1.0);
    final bg = Color.lerp(
      widget.isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurface,
      widget.accentColor.withValues(alpha: widget.isDark ? 0.28 : 0.16),
      p,
    )!;
    final iconColor = Color.lerp(widget.secondaryText, widget.accentColor, p)!;
    final pillHeight = (80.0 - (p * 26.0)).clamp(52.0, 80.0);

    return Container(
      width: 44,
      height: pillHeight,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.26 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.0 + p * 0.16,
            child: Icon(
              p > 0.68 ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 18,
              color: iconColor,
            ),
          ),
          if (p < 0.7) ...[
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: _chevronController,
              builder: (context, child) {
                final dy = -3.0 * _chevronController.value;
                return Opacity(
                  opacity: ((1.0 - p * 1.5) *
                          (0.45 + 0.55 * _chevronController.value))
                      .clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: child,
                  ),
                );
              },
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: iconColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulsingMicButton extends StatefulWidget {
  const _PulsingMicButton({
    required this.color,
    required this.isCanceling,
    required this.scale,
  });

  final Color color;
  final bool isCanceling;
  final double scale;

  @override
  State<_PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<_PulsingMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _haloController;

  @override
  void initState() {
    super.initState();
    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: widget.scale,
      child: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _haloController,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_haloController.value);
                return Container(
                  width: 50 + (t * 8),
                  height: 50 + (t * 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.22 - (t * 0.12)),
                  ),
                );
              },
            ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  widget.isCanceling
                      ? Icons.delete_rounded
                      : Icons.mic_rounded,
                  key: ValueKey(widget.isCanceling),
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingMicDot extends StatefulWidget {
  const _PulsingMicDot();

  @override
  State<_PulsingMicDot> createState() => _PulsingMicDotState();
}

class _PulsingMicDotState extends State<_PulsingMicDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LiveWaveform extends StatelessWidget {
  const _LiveWaveform({required this.amplitudes});

  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: double.infinity,
      child: CustomPaint(
        painter: _LiveWaveformPainter(
          amplitudes: List<double>.of(amplitudes, growable: false),
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  const _LiveWaveformPainter({
    required this.amplitudes,
    required this.color,
  });

  final List<double> amplitudes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    final count = amplitudes.length;
    final step = size.width / count;
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final amp = amplitudes[i].clamp(0.12, 1.0);
      final h = (24.0 * amp).clamp(3.0, size.height);
      final x = step * (i + 0.5);
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWaveformPainter oldDelegate) {
    if (oldDelegate.color != color) return true;
    if (oldDelegate.amplitudes.length != amplitudes.length) return true;
    for (var i = 0; i < amplitudes.length; i++) {
      if ((oldDelegate.amplitudes[i] - amplitudes[i]).abs() > 0.01) return true;
    }
    return false;
  }
}
