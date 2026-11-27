import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool isRecording = false;
  bool isLocked = false;
  bool isCanceling = false;
  Duration elapsed = Duration.zero;
  double dragDx = 0;
  double dragDy = 0;
  final List<double> liveAmplitudes =
      List<double>.filled(_barCount, 0.14, growable: true);

  Timer? _tickTimer;
  Timer? _ampTimer;
  DateTime? _startedAt;
  String? _currentPath;
  Offset? _pointerStart;
  bool _starting = false;
  bool _pointerReleasedDuringStart = false;
  Future<void>? _stopInFlight;

  Future<void> handlePointerDown(
    BuildContext context,
    PointerDownEvent event,
  ) async {
    if (isRecording || _starting) return;
    _starting = true;
    _pointerReleasedDuringStart = false;

    try {
      // Garante que qualquer gravação/cancelamento anterior terminou antes de gravar de novo.
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
      _pointerStart = event.position;
      _startedAt = DateTime.now();
      isRecording = true;
      isLocked = false;
      isCanceling = false;
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
    }
  }

  Future<void> _startRecorderWithSafeConfig(String filePath) async {
    // echoCancel e autoGain desligados para evitar silêncio em HALs Android fora de chamada VoIP;
    // noiseSuppress usa o supressor de ruído nativo do Android com qualidade padrão 44.1kHz / 64kbps.
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
      // Fallback caso algum aparelho não suporte o supressor nativo nessa taxa.
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

    dragDx = dx.clamp(-140.0, 0.0);
    dragDy = dy.clamp(-110.0, 0.0);
    isCanceling = dx < -95;

    if (dy < -72) {
      isLocked = true;
      isCanceling = false;
      dragDx = 0;
      dragDy = 0;
      HapticFeedback.lightImpact();
    }
    onStateChanged();
  }

  Future<void> handlePointerUpOrCancel() async {
    if (_starting && !isRecording) {
      _pointerReleasedDuringStart = true;
      return;
    }
    if (!isRecording || isLocked) return;

    if (isCanceling) {
      await cancelRecording();
      return;
    }

    final durationMs = _currentDurationMs();
    if (durationMs < 450) {
      // Toque rápido cancela silenciosamente sem mostrar avisos nem travar o botão.
      await cancelRecording();
      return;
    }

    await finishAndSend();
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
      if (!isRecording || _startedAt == null) return;
      final diff = DateTime.now().difference(_startedAt!);
      elapsed = diff;
      if (diff >= AppConstants.maxAudioDuration) {
        onFeedbackMessage('Limite de 3 minutos atingido. Enviando áudio...');
        await finishAndSend();
        return;
      }
      onStateChanged();
    });

    // Atualiza ~15 vezes por segundo com base na amplitude real do microfone (dBFS).
    _ampTimer = Timer.periodic(const Duration(milliseconds: 65), (_) async {
      if (!isRecording) return;
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
    if (_startedAt == null) return elapsed.inMilliseconds;
    return DateTime.now().difference(_startedAt!).inMilliseconds;
  }

  void _resetState() {
    isRecording = false;
    isLocked = false;
    isCanceling = false;
    elapsed = Duration.zero;
    dragDx = 0;
    dragDy = 0;
    _startedAt = null;
    _currentPath = null;
    _pointerStart = null;
  }

  Future<void> dispose() async {
    _stopTimers();
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

    if (controller.isLocked) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
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
            const SizedBox(width: 12),
            Expanded(
              child: _LiveWaveform(amplitudes: controller.liveAmplitudes),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                onPressed: controller.finishAndSend,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: controller.isCanceling
                      ? Theme.of(context).colorScheme.error
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
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
                        : _LiveWaveform(amplitudes: controller.liveAmplitudes),
                  ),
                  if (!controller.isCanceling) ...[
                    const SizedBox(width: 6),
                    Transform.translate(
                      offset: Offset(controller.dragDx * 0.25, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: secondaryText,
                          ),
                          Text(
                            'Cancelar',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Transform.translate(
            offset: Offset(controller.dragDx * 0.15, controller.dragDy * 0.35),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: controller.isCanceling
                    ? Theme.of(context).colorScheme.error
                    : AppColors.emerald,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                controller.isCanceling
                    ? Icons.delete_rounded
                    : Icons.mic_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: amplitudes.map((amp) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 3,
            height: (24 * amp).clamp(3.0, 24.0),
            decoration: BoxDecoration(
              color: AppColors.emerald,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }
}
