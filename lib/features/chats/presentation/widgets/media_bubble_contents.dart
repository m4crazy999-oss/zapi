import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../domain/chat_message.dart';

class ImageBubbleContent extends ConsumerStatefulWidget {
  const ImageBubbleContent({
    super.key,
    required this.message,
    required this.textColor,
    required this.fontSize,
    this.onImageTap,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  final ChatMessage message;
  final Color textColor;
  final double fontSize;
  final VoidCallback? onImageTap;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetryUpload;

  @override
  ConsumerState<ImageBubbleContent> createState() =>
      _ImageBubbleContentState();
}

class _ImageBubbleContentState extends ConsumerState<ImageBubbleContent> {
  static final Map<String, Uint8List> _thumbMemoryCache = {};
  File? _resolvedFullFile;
  bool _requestedFull = false;
  bool _awaitingManualDownload = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _resolveFullQuality();
  }

  @override
  void didUpdateWidget(covariant ImageBubbleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaId != widget.message.mediaId ||
        oldWidget.message.isUploading != widget.message.isUploading) {
      _requestedFull = false;
      _awaitingManualDownload = false;
      _resolveFullQuality();
    }
  }

  Future<bool> _hasWifiInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('eth') ||
            name.contains('en')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _resolveFullQuality({bool forceDownload = false}) async {
    final msg = widget.message;
    if ((!forceDownload && _requestedFull) ||
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
    final cache = ref.read(mediaCacheServiceProvider);

    try {
      final cached = await cache.getCachedChatMediaIfExists(
        chatId: msg.chatId,
        mediaId: msg.mediaId!,
        mimeType: msg.mimeType ?? 'image/jpeg',
      );
      if (cached != null && await cached.exists()) {
        if (mounted) {
          setState(() {
            _resolvedFullFile = cached;
            _awaitingManualDownload = false;
          });
        }
        return;
      }

      if (!forceDownload) {
        final mode = ref.read(chatPreferencesProvider).autoDownloadMedia;
        if (mode == 'never') {
          if (mounted) setState(() => _awaitingManualDownload = true);
          return;
        }
        if (mode == 'wifi' && !(await _hasWifiInterface())) {
          if (mounted) setState(() => _awaitingManualDownload = true);
          return;
        }
      }

      if (forceDownload && mounted) {
        setState(() => _downloading = true);
      }

      final file = await cache.getOrFetchChatMedia(
        chatId: msg.chatId,
        mediaId: msg.mediaId!,
        mimeType: msg.mimeType ?? 'image/jpeg',
      );
      if (mounted && file != null && await file.exists()) {
        setState(() {
          _resolvedFullFile = file;
          _awaitingManualDownload = false;
        });
      }
    } catch (_) {
      if (mounted && forceDownload) {
        ZapiToast.showError(
          context,
          'Não foi possível baixar esta foto.',
          bottomOffset: 80,
        );
      }
    } finally {
      if (mounted && _downloading) {
        setState(() => _downloading = false);
      }
    }
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
              : _awaitingManualDownload && !hasFullLocal && _resolvedFullFile == null
                  ? () => _resolveFullQuality(forceDownload: true)
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
                  if (_awaitingManualDownload &&
                      !hasFullLocal &&
                      _resolvedFullFile == null &&
                      !message.isUploading &&
                      !message.uploadFailed)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _downloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Baixar foto',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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
                fontSize: (widget.fontSize - 0.5).clamp(12.5, 17.5),
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

class VideoBubbleContent extends StatelessWidget {
  const VideoBubbleContent({
    super.key,
    required this.message,
    required this.textColor,
    required this.fontSize,
    this.onVideoTap,
    this.onCancelUpload,
    this.onRetryUpload,
  });

  final ChatMessage message;
  final Color textColor;
  final double fontSize;
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
                fontSize: (fontSize - 0.5).clamp(12.5, 17.5),
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

class FileBubbleContent extends ConsumerStatefulWidget {
  const FileBubbleContent({
    super.key,
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
  ConsumerState<FileBubbleContent> createState() => _FileBubbleContentState();
}

class _FileBubbleContentState extends ConsumerState<FileBubbleContent> {
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
