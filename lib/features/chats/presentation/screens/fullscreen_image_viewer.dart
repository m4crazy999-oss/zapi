import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../../core/utils/zapi_toast.dart';

class FullscreenImageViewer extends ConsumerStatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.senderName,
    required this.timeLabel,
    this.chatId,
    this.mediaId,
    this.mimeType,
    this.thumbnailBase64,
    this.imageUrl,
    this.localFilePath,
    this.caption,
  });

  final String senderName;
  final String timeLabel;
  final String? chatId;
  final String? mediaId;
  final String? mimeType;
  final String? thumbnailBase64;
  final String? imageUrl;
  final String? localFilePath;
  final String? caption;

  @override
  ConsumerState<FullscreenImageViewer> createState() =>
      _FullscreenImageViewerState();
}

class _FullscreenImageViewerState
    extends ConsumerState<FullscreenImageViewer> {
  final _transformationController = TransformationController();
  double _dragOffsetY = 0;
  bool _isSaving = false;
  bool _savedRecently = false;
  bool _showOverlay = true;
  File? _resolvedFile;
  bool _loadingFull = false;
  bool _loadFailed = false;
  Uint8List? _thumbBytes;

  @override
  void initState() {
    super.initState();
    _decodeThumb();
    _resolveFullImage();
  }

  void _decodeThumb() {
    final raw = widget.thumbnailBase64?.trim();
    if (raw == null || raw.isEmpty) return;
    try {
      _thumbBytes = base64Decode(raw);
    } catch (_) {}
  }

  Future<void> _resolveFullImage() async {
    if (widget.localFilePath != null &&
        await File(widget.localFilePath!).exists()) {
      if (mounted) {
        setState(() => _resolvedFile = File(widget.localFilePath!));
      }
      return;
    }

    if (widget.chatId == null ||
        widget.chatId!.isEmpty ||
        widget.mediaId == null ||
        widget.mediaId!.isEmpty) {
      return;
    }

    setState(() => _loadingFull = true);
    try {
      final file = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
            chatId: widget.chatId!,
            mediaId: widget.mediaId!,
            mimeType: widget.mimeType ?? 'image/jpeg',
          );
      if (!mounted) return;
      setState(() {
        _resolvedFile = file;
        _loadFailed = file == null;
        _loadingFull = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loadingFull = false;
      });
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  bool get _isZoomed {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    return scale > 1.05;
  }

  Future<void> _saveToGallery() async {
    if (_isSaving) return;

    final granted = await PermissionHelper.requestGallery(context);
    if (!granted || !mounted) return;

    setState(() {
      _isSaving = true;
      _savedRecently = false;
    });
    try {
      var fileToSave = _resolvedFile;
      if (fileToSave == null &&
          widget.chatId != null &&
          widget.mediaId != null) {
        fileToSave =
            await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
                  chatId: widget.chatId!,
                  mediaId: widget.mediaId!,
                  mimeType: widget.mimeType ?? 'image/jpeg',
                );
      }

      if (fileToSave == null || !await fileToSave.exists()) {
        throw Exception('Imagem indisponível.');
      }

      await Gal.putImage(fileToSave.path, album: 'Zapi');
      if (mounted) {
        setState(() => _savedRecently = true);
      }
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível salvar a foto na galeria.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgOpacity = (1.0 - (_dragOffsetY.abs() / 260)).clamp(0.25, 1.0);

    Widget content;
    if (_resolvedFile != null) {
      content = Image.file(
        _resolvedFile!,
        fit: BoxFit.contain,
      );
    } else if (_thumbBytes != null) {
      content = Stack(
        alignment: Alignment.center,
        children: [
          Image.memory(
            _thumbBytes!,
            fit: BoxFit.contain,
          ),
          if (_loadingFull)
            const CircularProgressIndicator(color: Colors.white),
        ],
      );
    } else if (_loadingFull) {
      content = const CircularProgressIndicator(color: Colors.white);
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      content = Image.network(
        widget.imageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_rounded,
          color: Colors.white54,
          size: 64,
        ),
      );
    } else if (_loadFailed) {
      content = const Icon(
        Icons.broken_image_rounded,
        color: Colors.white54,
        size: 64,
      );
    } else {
      content = const Icon(
        Icons.broken_image_rounded,
        color: Colors.white54,
        size: 64,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgOpacity),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showOverlay = !_showOverlay),
            onVerticalDragUpdate: _isZoomed
                ? null
                : (details) {
                    setState(() {
                      _dragOffsetY += details.delta.dy;
                    });
                  },
            onVerticalDragEnd: _isZoomed
                ? null
                : (details) {
                    if (_dragOffsetY.abs() > 110 ||
                        (details.primaryVelocity ?? 0).abs() > 750) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _dragOffsetY = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragOffsetY),
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 4.5,
                child: Center(child: content),
              ),
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
                  IconButton(
                    onPressed: _isSaving ? null : _saveToGallery,
                    tooltip: 'Salvar na galeria',
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
          if (_showOverlay &&
              widget.caption != null &&
              widget.caption!.trim().isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.62),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Text(
                    widget.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
