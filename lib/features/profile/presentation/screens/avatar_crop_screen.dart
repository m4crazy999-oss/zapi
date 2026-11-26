import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_colors.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({
    super.key,
    required this.imageBytes,
    this.title = 'Ajustar foto',
    this.confirmLabel = 'Confirmar foto',
    this.circularOverlay = true,
    this.isAnimated = false,
  });

  final Uint8List imageBytes;
  final String title;
  final String confirmLabel;
  final bool circularOverlay;
  final bool isAnimated;

  static Future<Uint8List?> open(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Ajustar foto',
    String confirmLabel = 'Confirmar foto',
    bool circularOverlay = true,
    bool isAnimated = false,
  }) {
    return Navigator.of(context, rootNavigator: true).push<Uint8List?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AvatarCropScreen(
          imageBytes: imageBytes,
          title: title,
          confirmLabel: confirmLabel,
          circularOverlay: circularOverlay,
          isAnimated: isAnimated,
        ),
      ),
    );
  }

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transformController =
      TransformationController();

  ui.Image? _decodedImage;
  double? _configuredCropSize;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isAnimated) {
      ui.decodeImageFromList(widget.imageBytes, (image) {
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _decodedImage = image;
        });
      });
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    _decodedImage?.dispose();
    super.dispose();
  }

  void _ensureInitialTransform(
    double cropSize,
    double displayW,
    double displayH,
  ) {
    if (_configuredCropSize == cropSize) return;
    _configuredCropSize = cropSize;
    final dx = -(displayW - cropSize) / 2;
    final dy = -(displayH - cropSize) / 2;
    _transformController.value = Matrix4.translationValues(dx, dy, 0);
  }

  void _resetZoom() {
    final decoded = _decodedImage;
    final cropSize = _configuredCropSize;
    if (decoded == null || cropSize == null) return;
    final shortSide = math.min(decoded.width, decoded.height).toDouble();
    final scale = shortSide > 0 ? cropSize / shortSide : 1.0;
    final displayW = decoded.width * scale;
    final displayH = decoded.height * scale;
    final dx = -(displayW - cropSize) / 2;
    final dy = -(displayH - cropSize) / 2;
    _transformController.value = Matrix4.translationValues(dx, dy, 0);
  }

  Future<void> _confirmCrop() async {
    if (_isConfirming) return;

    if (widget.isAnimated) {
      Navigator.pop(context, widget.imageBytes);
      return;
    }

    setState(() => _isConfirming = true);
    try {
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        if (mounted) Navigator.pop(context, widget.imageBytes);
        return;
      }

      final image = await renderObject.toImage(pixelRatio: 2.0);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted) return;
        if (byteData == null) {
          Navigator.pop(context, null);
          return;
        }
        Navigator.pop(context, byteData.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isConfirming = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível confirmar o recorte. Tente novamente.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B141A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title),
        actions: [
          if (!widget.isAnimated)
            IconButton(
              tooltip: 'Centralizar',
              onPressed: _isConfirming ? null : _resetZoom,
              icon: const Icon(Icons.center_focus_strong_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cropSize = math
                    .min(
                      constraints.maxWidth - 32,
                      constraints.maxHeight - 56,
                    )
                    .clamp(200.0, 380.0);

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isAnimated)
                        Container(
                          width: cropSize,
                          height: cropSize,
                          decoration: BoxDecoration(
                            shape: widget.circularOverlay
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                            borderRadius: widget.circularOverlay
                                ? null
                                : BorderRadius.circular(24),
                            border: Border.all(
                              color: AppColors.emeraldBright,
                              width: 2.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        )
                      else
                        _buildStaticCropArea(cropSize),
                      const SizedBox(height: 16),
                      Text(
                        widget.isAnimated
                            ? 'Foto animada pronta para aplicar no perfil'
                            : 'Arraste e use os dedos para ajustar o enquadramento',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF121E25),
                border: Border(
                  top: BorderSide(color: Color(0xFF233642)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isConfirming ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF334754)),
                        minimumSize: const Size(0, 52),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isConfirming ? null : _confirmCrop,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      icon: _isConfirming
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _isConfirming ? 'Aplicando...' : widget.confirmLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaticCropArea(double cropSize) {
    final decoded = _decodedImage;
    if (decoded == null) {
      return SizedBox(
        width: cropSize,
        height: cropSize,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.emeraldBright),
        ),
      );
    }

    final shortSide = math.min(decoded.width, decoded.height).toDouble();
    final baseScale = shortSide > 0 ? cropSize / shortSide : 1.0;
    final displayW = decoded.width * baseScale;
    final displayH = decoded.height * baseScale;
    _ensureInitialTransform(cropSize, displayW, displayH);

    return SizedBox(
      width: cropSize,
      height: cropSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              widget.circularOverlay ? cropSize / 2 : 20,
            ),
            child: RepaintBoundary(
              key: _boundaryKey,
              child: Container(
                width: cropSize,
                height: cropSize,
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  minScale: 1.0,
                  maxScale: 4.5,
                  boundaryMargin: EdgeInsets.all(cropSize * 0.25),
                  child: SizedBox(
                    width: displayW,
                    height: displayH,
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CropGuidePainter(circular: widget.circularOverlay),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropGuidePainter extends CustomPainter {
  const _CropGuidePainter({required this.circular});

  final bool circular;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (circular) {
      canvas.drawCircle(
        rect.center,
        (size.shortestSide / 2) - 1,
        borderPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(20)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropGuidePainter oldDelegate) =>
      oldDelegate.circular != circular;
}
