import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/media_cache_service.dart';

class ZapiStickerImage extends ConsumerStatefulWidget {
  const ZapiStickerImage({
    super.key,
    this.assetPath,
    this.dataBase64,
    this.chatId,
    this.mediaId,
    this.mimeType,
    this.size = 136,
  });

  final String? assetPath;
  final String? dataBase64;
  final String? chatId;
  final String? mediaId;
  final String? mimeType;
  final double size;

  @override
  ConsumerState<ZapiStickerImage> createState() => _ZapiStickerImageState();
}

class _ZapiStickerImageState extends ConsumerState<ZapiStickerImage> {
  static final Map<String, Uint8List> _memoryCache = {};
  File? _cachedFile;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMediaIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ZapiStickerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.mediaId != widget.mediaId) {
      _cachedFile = null;
      _failed = false;
      _loadMediaIfNeeded();
    }
  }

  Future<void> _loadMediaIfNeeded() async {
    if (widget.assetPath != null && widget.assetPath!.isNotEmpty) return;
    if (widget.dataBase64 != null && widget.dataBase64!.isNotEmpty) return;
    if (widget.chatId == null ||
        widget.chatId!.isEmpty ||
        widget.mediaId == null ||
        widget.mediaId!.isEmpty) {
      return;
    }

    setState(() => _loading = true);
    try {
      final file = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
            chatId: widget.chatId!,
            mediaId: widget.mediaId!,
            mimeType: widget.mimeType ?? 'image/webp',
          );
      if (!mounted) return;
      setState(() {
        _cachedFile = file;
        _failed = file == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Uint8List? _decodeInline() {
    final raw = widget.dataBase64?.trim();
    if (raw == null || raw.isEmpty) return null;
    final cached = _memoryCache[raw];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(raw);
      if (_memoryCache.length > 120) _memoryCache.clear();
      _memoryCache[raw] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assetPath != null && widget.assetPath!.startsWith('asset://')) {
      final path = widget.assetPath!.replaceFirst('asset://', '');
      return Image.asset(
        path,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _StickerFallback(size: widget.size),
      );
    }

    final inlineBytes = _decodeInline();
    if (inlineBytes != null) {
      return Image.memory(
        inlineBytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _StickerFallback(size: widget.size),
      );
    }

    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _StickerFallback(size: widget.size),
      );
    }

    if (_loading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return _StickerFallback(size: widget.size);
  }
}

class _StickerFallback extends StatelessWidget {
  const _StickerFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.sticky_note_2_outlined,
        size: size * 0.42,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
