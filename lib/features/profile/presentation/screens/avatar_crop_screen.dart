import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/zapi_toast.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({
    super.key,
    required this.imageBytes,
    this.title = 'Ajustar foto',
    this.confirmLabel = 'Confirmar foto',
    this.circularOverlay = true,
    this.isAnimated = false,
    this.aspectRatio = 1.0,
  });

  final Uint8List imageBytes;
  final String title;
  final String confirmLabel;
  final bool circularOverlay;
  final bool isAnimated;
  final double aspectRatio;

  static Future<Uint8List?> open(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Ajustar foto',
    String confirmLabel = 'Confirmar foto',
    bool circularOverlay = true,
    bool isAnimated = false,
    double aspectRatio = 1.0,
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
          aspectRatio: aspectRatio,
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
  Size? _configuredViewport;
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

  Size _computeViewportSize(BoxConstraints constraints) {
    final maxW = (constraints.maxWidth - 32).clamp(200.0, 420.0);
    final maxH = (constraints.maxHeight - 56).clamp(150.0, 380.0);
    final ratio = widget.aspectRatio <= 0 ? 1.0 : widget.aspectRatio;

    var w = maxW;
    var h = w / ratio;
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    return Size(w, h);
  }

  void _ensureInitialTransform(
    Size viewport,
    double displayW,
    double displayH,
  ) {
    if (_configuredViewport == viewport) return;
    _configuredViewport = viewport;
    final dx = -(displayW - viewport.width) / 2;
    final dy = -(displayH - viewport.height) / 2;
    _transformController.value = Matrix4.translationValues(dx, dy, 0);
  }

  void _resetZoom() {
    final decoded = _decodedImage;
    final viewport = _configuredViewport;
    if (decoded == null || viewport == null) return;
    final scale = math.max(
      viewport.width / math.max(1, decoded.width),
      viewport.height / math.max(1, decoded.height),
    );
    final displayW = decoded.width * scale;
    final displayH = decoded.height * scale;
    final dx = -(displayW - viewport.width) / 2;
    final dy = -(displayH - viewport.height) / 2;
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
        ZapiToast.showError(
          context,
          'Não foi possível confirmar o recorte. Tente novamente.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
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
                final viewport = _computeViewportSize(constraints);

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isAnimated)
                        Container(
                          width: viewport.width,
                          height: viewport.height,
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
                        _buildStaticCropArea(viewport),
                      const SizedBox(height: 16),
                      Text(
                        widget.isAnimated
                            ? 'Animação pronta para aplicar no perfil'
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
                color: AppColors.darkSurface,
                border: Border(
                  top: BorderSide(color: AppColors.darkBorder),
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

  Widget _buildStaticCropArea(Size viewport) {
    final decoded = _decodedImage;
    if (decoded == null) {
      return SizedBox(
        width: viewport.width,
        height: viewport.height,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.emeraldBright),
        ),
      );
    }

    final baseScale = math.max(
      viewport.width / math.max(1, decoded.width),
      viewport.height / math.max(1, decoded.height),
    );
    final displayW = decoded.width * baseScale;
    final displayH = decoded.height * baseScale;
    _ensureInitialTransform(viewport, displayW, displayH);

    return SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              widget.circularOverlay ? viewport.shortestSide / 2 : 20,
            ),
            child: RepaintBoundary(
              key: _boundaryKey,
              child: Container(
                width: viewport.width,
                height: viewport.height,
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  minScale: 1.0,
                  maxScale: 4.5,
                  boundaryMargin: EdgeInsets.all(viewport.shortestSide * 0.25),
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
