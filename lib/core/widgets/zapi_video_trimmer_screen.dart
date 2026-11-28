import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../constants/app_constants.dart';
import '../services/native_media_bridge.dart';
import '../theme/app_colors.dart';
import '../utils/app_exceptions.dart';
import '../utils/date_formatter.dart';
import '../utils/zapi_toast.dart';

class TrimmedVideoOutput {
  const TrimmedVideoOutput({
    required this.path,
    required this.durationMs,
    required this.sizeBytes,
    required this.caption,
  });

  final String path;
  final int durationMs;
  final int sizeBytes;
  final String caption;
}

class ZapiVideoTrimmerScreen extends StatefulWidget {
  const ZapiVideoTrimmerScreen({
    super.key,
    required this.videoPath,
    this.maxBytes = AppConstants.maxStatusVideoBytes,
    this.maxDurationMs = 60000,
    this.allowCaption = true,
    this.captionHint = 'Adicionar legenda...',
    this.primaryButtonLabel = 'Enviar vídeo',
  });

  final String videoPath;
  final int maxBytes;
  final int maxDurationMs;
  final bool allowCaption;
  final String captionHint;
  final String primaryButtonLabel;

  @override
  State<ZapiVideoTrimmerScreen> createState() => _ZapiVideoTrimmerScreenState();
}

class _ZapiVideoTrimmerScreenState extends State<ZapiVideoTrimmerScreen> {
  final _captionController = TextEditingController();
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _preparingOutput = false;
  String? _loadError;

  int _totalDurationMs = 0;
  int _startMs = 0;
  int _endMs = 0;
  int _originalSizeBytes = 0;
  bool _removeAudio = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        throw const AppException('Arquivo de vídeo não encontrado.');
      }
      _originalSizeBytes = await file.length();

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_removeAudio ? 0.0 : 1.0);
      controller.addListener(_onPlayerTick);

      final nativeMeta =
          await NativeMediaBridge.getVideoInfo(widget.videoPath);
      final playerDurMs = controller.value.duration.inMilliseconds;
      final total = nativeMeta != null && nativeMeta.durationMs > 0
          ? nativeMeta.durationMs
          : playerDurMs;

      final safeTotal = total > 0 ? total : 1000;
      final initialEnd = safeTotal.clamp(500, widget.maxDurationMs);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _totalDurationMs = safeTotal;
        _startMs = 0;
        _endMs = initialEnd;
        _loading = false;
      });
      await controller.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Não foi possível abrir este vídeo.';
        });
      }
    }
  }

  void _onPlayerTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final posMs = c.value.position.inMilliseconds;
    if (posMs >= _endMs || posMs < _startMs) {
      c.seekTo(Duration(milliseconds: _startMs));
    }
  }

  void _onRangeChanged(RangeValues values) {
    var nextStart = values.start.round().clamp(0, _totalDurationMs);
    var nextEnd = values.end.round().clamp(0, _totalDurationMs);

    if (nextEnd - nextStart < 500) {
      if (nextStart + 500 <= _totalDurationMs) {
        nextEnd = nextStart + 500;
      } else {
        nextStart = (nextEnd - 500).clamp(0, _totalDurationMs);
      }
    }

    if (nextEnd - nextStart > widget.maxDurationMs) {
      if ((nextStart - _startMs).abs() > (nextEnd - _endMs).abs()) {
        nextEnd = (nextStart + widget.maxDurationMs).clamp(0, _totalDurationMs);
      } else {
        nextStart = (nextEnd - widget.maxDurationMs).clamp(0, _totalDurationMs);
      }
    }

    setState(() {
      _startMs = nextStart;
      _endMs = nextEnd;
    });
    _controller?.seekTo(Duration(milliseconds: _startMs));
  }

  Future<void> _toggleRemoveAudio() async {
    final next = !_removeAudio;
    setState(() => _removeAudio = next);
    await _controller?.setVolume(next ? 0.0 : 1.0);
  }

  Future<void> _confirmAndTrim() async {
    if (_preparingOutput || _controller == null) return;
    setState(() => _preparingOutput = true);
    await _controller?.pause();

    try {
      final res = await NativeMediaBridge.trimAndCompressVideo(
        inputPath: widget.videoPath,
        startMs: _startMs,
        endMs: _endMs,
        maxBytes: widget.maxBytes,
        removeAudio: _removeAudio,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        TrimmedVideoOutput(
          path: res.path,
          durationMs: res.durationMs,
          sizeBytes: res.sizeBytes,
          caption: _captionController.text.trim(),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
      setState(() => _preparingOutput = false);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível preparar este vídeo agora.',
      );
      setState(() => _preparingOutput = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final selectedDuration =
        Duration(milliseconds: (_endMs - _startMs).clamp(0, widget.maxDurationMs));
    final maxDurLabel = DateFormatter.formatDuration(
      Duration(milliseconds: widget.maxDurationMs),
    );
    final originalSizeMb = (_originalSizeBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Recortar vídeo'),
        actions: [
          if (!_loading && _loadError == null)
            TextButton.icon(
              onPressed: _preparingOutput ? null : _toggleRemoveAudio,
              icon: Icon(
                _removeAudio
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: _removeAudio ? AppColors.emeraldBright : Colors.white,
                size: 20,
              ),
              label: Text(
                _removeAudio ? 'Sem áudio' : 'Com áudio',
                style: TextStyle(
                  color: _removeAudio ? AppColors.emeraldBright : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : (_loadError != null || controller == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _loadError ?? 'Vídeo indisponível.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (controller.value.isPlaying) {
                                controller.pause();
                              } else {
                                controller.play();
                              }
                              setState(() {});
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AspectRatio(
                                  aspectRatio: controller.value.aspectRatio > 0
                                      ? controller.value.aspectRatio
                                      : 9 / 16,
                                  child: VideoPlayer(controller),
                                ),
                                if (!controller.value.isPlaying)
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.56),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 38,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          color: AppColors.darkSurface,
                          child: SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.content_cut_rounded,
                                      color: AppColors.emeraldBright,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Trecho: ${DateFormatter.formatDuration(selectedDuration)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Máx $maxDurLabel · Orig. $originalSizeMb MB',
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_totalDurationMs > 500)
                                  RangeSlider(
                                    min: 0,
                                    max: _totalDurationMs.toDouble(),
                                    values: RangeValues(
                                      _startMs.toDouble(),
                                      _endMs.toDouble(),
                                    ),
                                    activeColor: AppColors.emerald,
                                    inactiveColor: Colors.white24,
                                    onChanged: _preparingOutput
                                        ? null
                                        : _onRangeChanged,
                                  ),
                                if (widget.allowCaption) ...[
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _captionController,
                                    enabled: !_preparingOutput,
                                    maxLength: AppConstants.maxMessageLength,
                                    minLines: 1,
                                    maxLines: 2,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: widget.captionHint,
                                      hintStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      filled: true,
                                      fillColor: AppColors.darkSurfaceAlt,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 11,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: FilledButton.icon(
                                    onPressed: _preparingOutput
                                        ? null
                                        : _confirmAndTrim,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.emerald,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: const Icon(Icons.send_rounded),
                                    label: Text(
                                      widget.primaryButtonLabel,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_preparingOutput)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.72),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: AppColors.emeraldBright,
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Preparando vídeo...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
