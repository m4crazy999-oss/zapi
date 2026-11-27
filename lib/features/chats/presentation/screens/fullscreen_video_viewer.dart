import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../../core/utils/zapi_toast.dart';

class FullscreenVideoViewer extends ConsumerStatefulWidget {
  const FullscreenVideoViewer({
    super.key,
    required this.senderName,
    required this.timeLabel,
    this.chatId,
    this.mediaId,
    this.mimeType,
    this.localFilePath,
    this.caption,
  });

  final String senderName;
  final String timeLabel;
  final String? chatId;
  final String? mediaId;
  final String? mimeType;
  final String? localFilePath;
  final String? caption;

  @override
  ConsumerState<FullscreenVideoViewer> createState() =>
      _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends ConsumerState<FullscreenVideoViewer> {
  VideoPlayerController? _controller;
  File? _resolvedFile;
  bool _loading = true;
  bool _failed = false;
  bool _isSaving = false;
  bool _savedRecently = false;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _initVideo() async {
    try {
      File? file;
      if (widget.localFilePath != null &&
          await File(widget.localFilePath!).exists()) {
        file = File(widget.localFilePath!);
      } else if (widget.chatId != null &&
          widget.chatId!.isNotEmpty &&
          widget.mediaId != null &&
          widget.mediaId!.isNotEmpty) {
        file = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
              chatId: widget.chatId!,
              mediaId: widget.mediaId!,
              mimeType: widget.mimeType ?? 'video/mp4',
            );
      }

      if (file == null || !await file.exists()) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
        return;
      }

      _resolvedFile = file;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      controller.addListener(_onPlayerUpdate);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_isSaving || _resolvedFile == null) return;
    final granted = await PermissionHelper.requestGallery(
      context,
      includeVideo: true,
    );
    if (!granted || !mounted) return;

    setState(() {
      _isSaving = true;
      _savedRecently = false;
    });
    try {
      await Gal.putVideo(_resolvedFile!.path, album: 'Zapi');
      if (!mounted) return;
      setState(() => _savedRecently = true);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível salvar o vídeo na galeria.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showOverlay = !_showOverlay),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_failed || c == null || !c.value.isInitialized)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam_off_rounded,
                      color: Colors.white54,
                      size: 56,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Não foi possível reproduzir este vídeo.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: AspectRatio(
                  aspectRatio:
                      c.value.aspectRatio > 0 ? c.value.aspectRatio : 9 / 16,
                  child: VideoPlayer(c),
                ),
              ),

            if (_showOverlay)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppBar(
                  backgroundColor: Colors.black.withValues(alpha: 0.55),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.senderName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.timeLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    if (_resolvedFile != null)
                      IconButton(
                        tooltip: 'Salvar na galeria',
                        onPressed: _isSaving ? null : _saveToGallery,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _savedRecently
                                    ? Icons.check_rounded
                                    : Icons.download_rounded,
                              ),
                      ),
                  ],
                ),
              ),

            if (_showOverlay && c != null && c.value.isInitialized)
              Center(
                child: GestureDetector(
                  onTap: () {
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      c.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
              ),

            if (_showOverlay && c != null && c.value.isInitialized)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.caption != null &&
                            widget.caption!.trim().isNotEmpty) ...[
                          Text(
                            widget.caption!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Text(
                              DateFormatter.formatDuration(c.value.position),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: c.value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0.0,
                                      c.value.duration.inMilliseconds
                                          .toDouble()
                                          .clamp(1.0, double.infinity),
                                    ),
                                min: 0,
                                max: c.value.duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1.0, double.infinity),
                                activeColor: AppColors.emeraldBright,
                                inactiveColor: Colors.white24,
                                onChanged: (ms) {
                                  c.seekTo(Duration(milliseconds: ms.round()));
                                },
                              ),
                            ),
                            Text(
                              DateFormatter.formatDuration(c.value.duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
