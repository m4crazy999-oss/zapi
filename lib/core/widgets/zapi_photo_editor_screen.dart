import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/stickers/data/unicode_emoji_data.dart';
import '../../features/stickers/domain/zapi_sticker.dart';
import '../../features/stickers/presentation/providers/stickers_providers.dart';
import '../../features/stickers/presentation/widgets/zapi_sticker_image.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../utils/zapi_toast.dart';

enum _EditorTool {
  none,
  draw,
  crop,
}

class _DrawStroke {
  _DrawStroke({
    required this.points,
    required this.color,
    required this.widthFraction,
  });

  final List<Offset> points; // coordenadas normalizadas 0..1 sobre a foto
  final Color color;
  final double widthFraction; // proporção da largura da foto
}

class _TextOverlayItem {
  _TextOverlayItem({
    required this.id,
    required this.text,
    required this.color,
    required this.fontKey,
    required this.withPill,
    this.nx = 0.5,
    this.ny = 0.45,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final String id;
  String text;
  Color color;
  String fontKey; // 'sans' | 'serif' | 'mono' | 'display'
  bool withPill;
  double nx;
  double ny;
  double scale;
  double rotation;
}

class _StickerOverlayItem {
  _StickerOverlayItem({
    required this.id,
    this.emoji,
    this.stickerImage,
    this.stickerBytes,
    this.nx = 0.5,
    this.ny = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final String id;
  final String? emoji;
  final ui.Image? stickerImage;
  final Uint8List? stickerBytes;
  double nx;
  double ny;
  double scale;
  double rotation;
}

class _EditablePhotoDoc {
  _EditablePhotoDoc({
    required this.originalPath,
    required this.baseImage,
    this.caption = '',
  });

  final String originalPath;
  ui.Image baseImage;
  String caption;

  final List<_DrawStroke> strokes = [];
  final List<_DrawStroke> redoStrokes = [];
  final List<_TextOverlayItem> textOverlays = [];
  final List<_StickerOverlayItem> stickerOverlays = [];

  void disposeImages() {
    baseImage.dispose();
    for (final s in stickerOverlays) {
      s.stickerImage?.dispose();
    }
  }
}

class ZapiPhotoEditorScreen extends ConsumerStatefulWidget {
  const ZapiPhotoEditorScreen({
    super.key,
    required this.initialPaths,
    this.recipientName,
    this.sendButtonLabel,
    this.captionHint = 'Adicionar legenda...',
  });

  final List<String> initialPaths;
  final String? recipientName;
  final String? sendButtonLabel;
  final String captionHint;

  @override
  ConsumerState<ZapiPhotoEditorScreen> createState() =>
      _ZapiPhotoEditorScreenState();
}

class _ZapiPhotoEditorScreenState extends ConsumerState<ZapiPhotoEditorScreen> {
  static const _uuid = Uuid();
  static const List<Color> _palette = [
    Color(0xFFFFFFFF),
    Color(0xFF111827),
    Color(0xFF00A884),
    Color(0xFF38BDF8),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFA855F7),
    Color(0xFFEC4899),
  ];

  final _captionController = TextEditingController();
  final List<_EditablePhotoDoc> _docs = [];
  int _activeIndex = 0;
  bool _loadingDocs = true;
  bool _exporting = false;

  _EditorTool _tool = _EditorTool.none;
  Color _drawColor = _palette[5];
  double _strokeWidthFraction = 0.011;
  _DrawStroke? _activeStroke;

  // Estado temporário do modo Recorte
  Rect _cropRect = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
  double? _cropAspect;

  // Arraste/escala de figurinha ou texto ativo
  bool _isDraggingOverlay = false;
  bool _overTrash = false;
  String? _activeOverlayId;
  bool _activeOverlayIsText = false;
  Offset? _lastFocalPoint;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAllImages();
  }

  @override
  void dispose() {
    _captionController.dispose();
    for (final doc in _docs) {
      doc.disposeImages();
    }
    super.dispose();
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1440,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  Future<void> _loadAllImages() async {
    for (final path in widget.initialPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        final image = await _decodeUiImage(bytes);
        _docs.add(_EditablePhotoDoc(originalPath: path, baseImage: image));
      } catch (_) {}
    }

    if (!mounted) return;
    if (_docs.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _loadingDocs = false;
      _captionController.text = _docs.first.caption;
    });
  }

  _EditablePhotoDoc get _currentDoc => _docs[_activeIndex];

  void _switchPhoto(int index) {
    if (index == _activeIndex || index < 0 || index >= _docs.length) return;
    _currentDoc.caption = _captionController.text;
    setState(() {
      _activeIndex = index;
      _tool = _EditorTool.none;
      _captionController.text = _currentDoc.caption;
    });
  }

  void _removeCurrentPhoto() {
    if (_docs.length <= 1) {
      Navigator.pop(context);
      return;
    }
    final removed = _docs.removeAt(_activeIndex);
    removed.disposeImages();
    setState(() {
      if (_activeIndex >= _docs.length) _activeIndex = _docs.length - 1;
      _captionController.text = _currentDoc.caption;
      _tool = _EditorTool.none;
    });
  }

  Future<void> _rotate90() async {
    final doc = _currentDoc;
    final src = doc.baseImage;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(src.height.toDouble(), 0);
    canvas.rotate(math.pi / 2);
    canvas.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    final picture = recorder.endRecording();
    final rotated = await picture.toImage(src.height, src.width);
    picture.dispose();

    // Rotaciona coordenadas dos traços e overlays também
    for (final stroke in doc.strokes) {
      for (var i = 0; i < stroke.points.length; i++) {
        final pt = stroke.points[i];
        stroke.points[i] = Offset(1.0 - pt.dy, pt.dx);
      }
    }
    for (final t in doc.textOverlays) {
      final oldX = t.nx;
      t.nx = 1.0 - t.ny;
      t.ny = oldX;
      t.rotation += math.pi / 2;
    }
    for (final s in doc.stickerOverlays) {
      final oldX = s.nx;
      s.nx = 1.0 - s.ny;
      s.ny = oldX;
      s.rotation += math.pi / 2;
    }

    src.dispose();
    setState(() {
      doc.baseImage = rotated;
    });
  }

  Future<void> _applyCrop() async {
    final doc = _currentDoc;
    final src = doc.baseImage;
    final left = (_cropRect.left * src.width).round().clamp(0, src.width - 10);
    final top = (_cropRect.top * src.height).round().clamp(0, src.height - 10);
    final right =
        (_cropRect.right * src.width).round().clamp(left + 10, src.width);
    final bottom =
        (_cropRect.bottom * src.height).round().clamp(top + 10, src.height);
    final outW = (right - left).clamp(10, src.width);
    final outH = (bottom - top).clamp(10, src.height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        outW.toDouble(),
        outH.toDouble(),
      ),
      Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(outW, outH);
    picture.dispose();

    // Remapeia traços e elementos para o novo quadro recortado
    final rw = _cropRect.width;
    final rh = _cropRect.height;
    for (final stroke in doc.strokes) {
      for (var i = 0; i < stroke.points.length; i++) {
        final pt = stroke.points[i];
        stroke.points[i] = Offset(
          (pt.dx - _cropRect.left) / rw,
          (pt.dy - _cropRect.top) / rh,
        );
      }
    }
    for (final t in doc.textOverlays) {
      t.nx = ((t.nx - _cropRect.left) / rw).clamp(0.08, 0.92);
      t.ny = ((t.ny - _cropRect.top) / rh).clamp(0.08, 0.92);
    }
    for (final s in doc.stickerOverlays) {
      s.nx = ((s.nx - _cropRect.left) / rw).clamp(0.08, 0.92);
      s.ny = ((s.ny - _cropRect.top) / rh).clamp(0.08, 0.92);
    }

    src.dispose();
    setState(() {
      doc.baseImage = cropped;
      _tool = _EditorTool.none;
      _cropRect = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
      _cropAspect = null;
    });
  }

  void _setCropAspect(double? aspect) {
    final img = _currentDoc.baseImage;
    final imgRatio = img.width / img.height;
    if (aspect == null) {
      setState(() {
        _cropAspect = null;
        _cropRect = const Rect.fromLTWH(0.06, 0.06, 0.88, 0.88);
      });
      return;
    }

    // Relação normalizada w/h para atingir aspect desejado em pixels
    final normRatio = aspect / imgRatio;
    double w = 0.88;
    double h = w / normRatio;
    if (h > 0.88) {
      h = 0.88;
      w = h * normRatio;
    }
    setState(() {
      _cropAspect = aspect;
      _cropRect = Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
    });
  }

  TextStyle _buildOverlayTextStyle({
    required String fontKey,
    required Color color,
    required double fontSize,
  }) {
    final shadow = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.48),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];

    return switch (fontKey) {
      'serif' => TextStyle(
          fontFamily: 'serif',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: shadow,
        ),
      'mono' => TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: shadow,
        ),
      'display' => TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
          color: color,
          shadows: shadow,
        ),
      _ => TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: color,
          shadows: shadow,
        ),
    };
  }

  Future<void> _openTextDialog({_TextOverlayItem? editing}) async {
    final controller = TextEditingController(text: editing?.text ?? '');
    var pickedColor = editing?.color ?? Colors.white;
    var fontKey = editing?.fontKey ?? 'sans';
    var withPill = editing?.withPill ?? false;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final fonts = [
              ('sans', 'Moderna'),
              ('serif', 'Clássica'),
              ('mono', 'Máquina'),
              ('display', 'Destaque'),
            ];
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Fundo no texto',
                        onPressed: () =>
                            setModalState(() => withPill = !withPill),
                        icon: Icon(
                          withPill
                              ? Icons.format_color_fill_rounded
                              : Icons.text_fields_rounded,
                          color: Colors.white,
                        ),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        child: const Text('Pronto'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: withPill
                          ? pickedColor.withValues(alpha: 0.24)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: 4,
                      minLines: 1,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.sentences,
                      style: _buildOverlayTextStyle(
                        fontKey: fontKey,
                        color: pickedColor,
                        fontSize: 24,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Digite seu texto...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in fonts)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                f.$2,
                                style: TextStyle(
                                  color: fontKey == f.$1
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              selected: fontKey == f.$1,
                              selectedColor: AppColors.emerald,
                              backgroundColor: AppColors.darkSurfaceAlt,
                              side: BorderSide(
                                color: fontKey == f.$1
                                    ? AppColors.emeraldBright
                                    : Colors.white24,
                              ),
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setModalState(() => fontKey = f.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _palette.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, idx) {
                        final c = _palette[idx];
                        final selected = c == pickedColor;
                        return GestureDetector(
                          onTap: () => setModalState(() => pickedColor = c),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? AppColors.emeraldBright
                                    : Colors.white38,
                                width: selected ? 3 : 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) {
      controller.dispose();
      return;
    }

    final text = controller.text.trim();
    controller.dispose();
    if (text.isEmpty) {
      if (editing != null) {
        setState(() {
          _currentDoc.textOverlays.removeWhere((t) => t.id == editing.id);
        });
      }
      return;
    }

    setState(() {
      if (editing != null) {
        editing
          ..text = text
          ..color = pickedColor
          ..fontKey = fontKey
          ..withPill = withPill;
      } else {
        _currentDoc.textOverlays.add(
          _TextOverlayItem(
            id: _uuid.v4(),
            text: text,
            color: pickedColor,
            fontKey: fontKey,
            withPill: withPill,
          ),
        );
      }
      _tool = _EditorTool.none;
    });
  }

  Future<void> _openEmojiAndStickerSheet() async {
    final stickers = ref.read(allAvailableStickersProvider);
    final selected = await showModalBottomSheet<_StickerPickerChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      builder: (_) => _EditorStickerSheet(customStickers: stickers),
    );
    if (selected == null || !mounted) return;

    if (selected.emoji != null) {
      setState(() {
        _currentDoc.stickerOverlays.add(
          _StickerOverlayItem(
            id: _uuid.v4(),
            emoji: selected.emoji,
          ),
        );
        _tool = _EditorTool.none;
      });
      return;
    }

    final sticker = selected.sticker;
    final b64 = sticker?.dataBase64;
    if (b64 == null || b64.isEmpty) return;

    try {
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _currentDoc.stickerOverlays.add(
          _StickerOverlayItem(
            id: _uuid.v4(),
            stickerImage: frame.image,
            stickerBytes: bytes,
          ),
        );
        _tool = _EditorTool.none;
      });
    } catch (_) {}
  }

  Future<void> _exportAndReturn() async {
    if (_exporting) return;
    _currentDoc.caption = _captionController.text.trim();
    setState(() => _exporting = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final outDir = Directory(p.join(tempDir.path, 'zapi_edited_photos'));
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final outputs = <({String sourcePath, String caption})>[];
      for (final doc in _docs) {
        final renderedPath = await _bakeDocumentToFile(doc, outDir.path);
        outputs.add((sourcePath: renderedPath, caption: doc.caption.trim()));
      }

      if (!mounted) return;
      Navigator.pop(context, outputs);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível preparar a foto editada.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<String> _bakeDocumentToFile(
    _EditablePhotoDoc doc,
    String outDirPath,
  ) async {
    final src = doc.baseImage;
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Imagem base
    canvas.drawImage(
      src,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );

    // 2. Traços de desenho livre
    for (final stroke in doc.strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = (stroke.widthFraction * w).clamp(2.0, 28.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        final pt = Offset(stroke.points.first.dx * w, stroke.points.first.dy * h);
        canvas.drawCircle(pt, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path()
          ..moveTo(stroke.points.first.dx * w, stroke.points.first.dy * h);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx * w, stroke.points[i].dy * h);
        }
        canvas.drawPath(path, paint);
      }
    }

    // 3. Figurinhas e emojis
    final baseUnit = math.min(w, h);
    for (final item in doc.stickerOverlays) {
      canvas.save();
      canvas.translate(item.nx * w, item.ny * h);
      canvas.rotate(item.rotation);
      canvas.scale(item.scale);

      if (item.emoji != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: item.emoji,
            style: TextStyle(fontSize: baseUnit * 0.14),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      } else if (item.stickerImage != null) {
        final targetSize = baseUnit * 0.24;
        final img = item.stickerImage!;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCenter(
            center: Offset.zero,
            width: targetSize,
            height: targetSize,
          ),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      canvas.restore();
    }

    // 4. Textos sobrepostos
    for (final textItem in doc.textOverlays) {
      canvas.save();
      canvas.translate(textItem.nx * w, textItem.ny * h);
      canvas.rotate(textItem.rotation);
      canvas.scale(textItem.scale);

      final tp = TextPainter(
        text: TextSpan(
          text: textItem.text,
          style: _buildOverlayTextStyle(
            fontKey: textItem.fontKey,
            color: textItem.color,
            fontSize: (baseUnit * 0.068).clamp(24.0, 72.0),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w * 0.86);

      if (textItem.withPill) {
        final pillColor = textItem.color.computeLuminance() > 0.6
            ? Colors.black.withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.85);
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: tp.width + baseUnit * 0.05,
            height: tp.height + baseUnit * 0.03,
          ),
          Radius.circular(baseUnit * 0.02),
        );
        canvas.drawRRect(rect, Paint()..color = pillColor);
      }

      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(src.width, src.height);
    picture.dispose();

    final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    if (byteData == null) {
      return doc.originalPath;
    }

    final outPath = p.join(outDirPath, 'edited_${_uuid.v4()}.png');
    await File(outPath).writeAsBytes(
      byteData.buffer.asUint8List(),
      flush: true,
    );
    return outPath;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDocs) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final doc = _currentDoc;
    final img = doc.baseImage;
    final imgAspect = img.width / img.height;

    final primaryButtonLabel = widget.sendButtonLabel ??
        (_docs.length > 1
            ? 'Enviar ${_docs.length} fotos'
            : (widget.recipientName != null
                ? 'Enviar para ${widget.recipientName}'
                : 'Enviar foto'));

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior de ferramentas
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Fechar editor',
                    onPressed: _exporting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  if (_tool == _EditorTool.draw) ...[
                    IconButton(
                      tooltip: 'Desfazer traço',
                      onPressed: doc.strokes.isEmpty
                          ? null
                          : () {
                              setState(() {
                                doc.redoStrokes.add(doc.strokes.removeLast());
                              });
                            },
                      icon: Icon(
                        Icons.undo_rounded,
                        color: doc.strokes.isEmpty
                            ? Colors.white30
                            : Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refazer traço',
                      onPressed: doc.redoStrokes.isEmpty
                          ? null
                          : () {
                              setState(() {
                                doc.strokes.add(doc.redoStrokes.removeLast());
                              });
                            },
                      icon: Icon(
                        Icons.redo_rounded,
                        color: doc.redoStrokes.isEmpty
                            ? Colors.white30
                            : Colors.white,
                      ),
                    ),
                  ],
                  _EditorToolButton(
                    icon: Icons.crop_rotate_rounded,
                    tooltip: 'Recortar e girar',
                    active: _tool == _EditorTool.crop,
                    onTap: () => setState(() {
                      _tool = _tool == _EditorTool.crop
                          ? _EditorTool.none
                          : _EditorTool.crop;
                      _cropRect = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
                      _cropAspect = null;
                    }),
                  ),
                  _EditorToolButton(
                    icon: Icons.brush_rounded,
                    tooltip: 'Desenhar',
                    active: _tool == _EditorTool.draw,
                    onTap: () => setState(() {
                      _tool = _tool == _EditorTool.draw
                          ? _EditorTool.none
                          : _EditorTool.draw;
                    }),
                  ),
                  _EditorToolButton(
                    icon: Icons.title_rounded,
                    tooltip: 'Adicionar texto',
                    active: false,
                    onTap: () => _openTextDialog(),
                  ),
                  _EditorToolButton(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    tooltip: 'Emojis e figurinhas',
                    active: false,
                    onTap: _openEmojiAndStickerSheet,
                  ),
                  if (_docs.length > 1)
                    _EditorToolButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Remover esta foto',
                      active: false,
                      onTap: _removeCurrentPhoto,
                    ),
                ],
              ),
            ),

            // Controles contextuais do modo Desenhar
            if (_tool == _EditorTool.draw)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    // Espessuras do pincel
                    for (final w in [0.006, 0.011, 0.019])
                      GestureDetector(
                        onTap: () => setState(() => _strokeWidthFraction = w),
                        child: Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: _strokeWidthFraction == w
                                ? Colors.white24
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: w * 700,
                              height: w * 700,
                              decoration: BoxDecoration(
                                color: _drawColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _palette.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final c = _palette[idx];
                            final selected = c == _drawColor;
                            return GestureDetector(
                              onTap: () => setState(() => _drawColor = c),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.emeraldBright
                                        : Colors.white54,
                                    width: selected ? 3 : 1.5,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Controles contextuais do modo Recorte e Giro
            if (_tool == _EditorTool.crop)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Girar 90°',
                      onPressed: _rotate90,
                      icon: const Icon(
                        Icons.rotate_right_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _CropChip(
                              label: 'Livre',
                              selected: _cropAspect == null,
                              onTap: () => _setCropAspect(null),
                            ),
                            _CropChip(
                              label: '1:1',
                              selected: _cropAspect == 1.0,
                              onTap: () => _setCropAspect(1.0),
                            ),
                            _CropChip(
                              label: '4:3',
                              selected: _cropAspect == 4 / 3,
                              onTap: () => _setCropAspect(4 / 3),
                            ),
                            _CropChip(
                              label: '16:9',
                              selected: _cropAspect == 16 / 9,
                              onTap: () => _setCropAspect(16 / 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: _applyCrop,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Recortar'),
                    ),
                  ],
                ),
              ),

            // Área principal da imagem com desenho, textos, emojis/figurinhas e recorte
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: imgAspect,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cw = constraints.maxWidth;
                      final ch = constraints.maxHeight;
                      final baseUnit = math.min(cw, ch);

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: RawImage(
                              image: img,
                              fit: BoxFit.fill,
                            ),
                          ),
                          // Camada de desenho livre
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CanvasStrokesPainter(
                                strokes: doc.strokes,
                                activeStroke: _activeStroke,
                              ),
                            ),
                          ),
                          // Captura de desenho quando modo Draw ativo
                          if (_tool == _EditorTool.draw)
                            Positioned.fill(
                              child: GestureDetector(
                                onPanStart: (d) {
                                  final pt = Offset(
                                    (d.localPosition.dx / cw).clamp(0.0, 1.0),
                                    (d.localPosition.dy / ch).clamp(0.0, 1.0),
                                  );
                                  setState(() {
                                    doc.redoStrokes.clear();
                                    _activeStroke = _DrawStroke(
                                      points: [pt],
                                      color: _drawColor,
                                      widthFraction: _strokeWidthFraction,
                                    );
                                  });
                                },
                                onPanUpdate: (d) {
                                  if (_activeStroke == null) return;
                                  final pt = Offset(
                                    (d.localPosition.dx / cw).clamp(0.0, 1.0),
                                    (d.localPosition.dy / ch).clamp(0.0, 1.0),
                                  );
                                  setState(() {
                                    _activeStroke!.points.add(pt);
                                  });
                                },
                                onPanEnd: (_) {
                                  if (_activeStroke != null) {
                                    setState(() {
                                      doc.strokes.add(_activeStroke!);
                                      _activeStroke = null;
                                    });
                                  }
                                },
                              ),
                            ),

                          // Emojis e figurinhas interativos
                          for (final item in doc.stickerOverlays)
                            Positioned(
                              left: item.nx * cw,
                              top: item.ny * ch,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: GestureDetector(
                                  onScaleStart: _tool != _EditorTool.none
                                      ? null
                                      : (d) {
                                          setState(() {
                                            _activeOverlayId = item.id;
                                            _activeOverlayIsText = false;
                                            _isDraggingOverlay = true;
                                            _overTrash = false;
                                            _lastFocalPoint = d.focalPoint;
                                            _gestureStartScale = item.scale;
                                            _gestureStartRotation =
                                                item.rotation;
                                          });
                                        },
                                  onScaleUpdate: _tool != _EditorTool.none
                                      ? null
                                      : (d) {
                                          final delta = d.focalPoint -
                                              (_lastFocalPoint ?? d.focalPoint);
                                          _lastFocalPoint = d.focalPoint;
                                          setState(() {
                                            item.nx = (item.nx + delta.dx / cw)
                                                .clamp(0.04, 0.96);
                                            item.ny = (item.ny + delta.dy / ch)
                                                .clamp(0.04, 1.04);
                                            item.scale = (_gestureStartScale *
                                                    d.scale)
                                                .clamp(0.4, 3.6);
                                            item.rotation =
                                                _gestureStartRotation +
                                                    d.rotation;
                                            _overTrash = item.ny > 0.87;
                                          });
                                        },
                                  onScaleEnd: _tool != _EditorTool.none
                                      ? null
                                      : (_) {
                                          setState(() {
                                            if (_overTrash) {
                                              doc.stickerOverlays.removeWhere(
                                                (e) => e.id == item.id,
                                              );
                                            }
                                            _isDraggingOverlay = false;
                                            _overTrash = false;
                                            _activeOverlayId = null;
                                          });
                                        },
                                  child: Transform.rotate(
                                    angle: item.rotation,
                                    child: Transform.scale(
                                      scale: item.scale,
                                      child: item.emoji != null
                                          ? Text(
                                              item.emoji!,
                                              style: TextStyle(
                                                fontSize: baseUnit * 0.14,
                                              ),
                                            )
                                          : (item.stickerBytes != null
                                              ? Image.memory(
                                                  item.stickerBytes!,
                                                  width: baseUnit * 0.24,
                                                  height: baseUnit * 0.24,
                                                  fit: BoxFit.contain,
                                                )
                                              : const SizedBox.shrink()),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Textos sobrepostos interativos
                          for (final t in doc.textOverlays)
                            Positioned(
                              left: t.nx * cw,
                              top: t.ny * ch,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, -0.5),
                                child: GestureDetector(
                                  onTap: _tool == _EditorTool.none
                                      ? () => _openTextDialog(editing: t)
                                      : null,
                                  onScaleStart: _tool != _EditorTool.none
                                      ? null
                                      : (d) {
                                          setState(() {
                                            _activeOverlayId = t.id;
                                            _activeOverlayIsText = true;
                                            _isDraggingOverlay = true;
                                            _overTrash = false;
                                            _lastFocalPoint = d.focalPoint;
                                            _gestureStartScale = t.scale;
                                            _gestureStartRotation = t.rotation;
                                          });
                                        },
                                  onScaleUpdate: _tool != _EditorTool.none
                                      ? null
                                      : (d) {
                                          final delta = d.focalPoint -
                                              (_lastFocalPoint ?? d.focalPoint);
                                          _lastFocalPoint = d.focalPoint;
                                          setState(() {
                                            t.nx = (t.nx + delta.dx / cw)
                                                .clamp(0.05, 0.95);
                                            t.ny = (t.ny + delta.dy / ch)
                                                .clamp(0.05, 1.04);
                                            t.scale = (_gestureStartScale *
                                                    d.scale)
                                                .clamp(0.5, 3.2);
                                            t.rotation =
                                                _gestureStartRotation +
                                                    d.rotation;
                                            _overTrash = t.ny > 0.87;
                                          });
                                        },
                                  onScaleEnd: _tool != _EditorTool.none
                                      ? null
                                      : (_) {
                                          setState(() {
                                            if (_overTrash) {
                                              doc.textOverlays.removeWhere(
                                                (e) => e.id == t.id,
                                              );
                                            }
                                            _isDraggingOverlay = false;
                                            _overTrash = false;
                                            _activeOverlayId = null;
                                          });
                                        },
                                  child: Transform.rotate(
                                    angle: t.rotation,
                                    child: Transform.scale(
                                      scale: t.scale,
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: cw * 0.86,
                                        ),
                                        padding: t.withPill
                                            ? const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              )
                                            : EdgeInsets.zero,
                                        decoration: t.withPill
                                            ? BoxDecoration(
                                                color: t.color
                                                            .computeLuminance() >
                                                        0.6
                                                    ? Colors.black.withValues(
                                                        alpha: 0.6,
                                                      )
                                                    : Colors.white.withValues(
                                                        alpha: 0.85,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              )
                                            : null,
                                        child: Text(
                                          t.text,
                                          textAlign: TextAlign.center,
                                          style: _buildOverlayTextStyle(
                                            fontKey: t.fontKey,
                                            color: t.color,
                                            fontSize: (baseUnit * 0.068)
                                                .clamp(18.0, 38.0),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // Área de exclusão ao arrastar texto/emoji/figurinha para baixo
                          if (_isDraggingOverlay && _activeOverlayId != null)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _overTrash
                                        ? const Color(0xFFDC2626)
                                        : Colors.black.withValues(alpha: 0.68),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: _overTrash
                                          ? Colors.white
                                          : Colors.white38,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.delete_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _overTrash
                                            ? 'Solte para apagar'
                                            : (_activeOverlayIsText
                                                ? 'Arraste aqui para apagar texto'
                                                : 'Arraste aqui para apagar'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          // Grade interativa do modo Recorte
                          if (_tool == _EditorTool.crop)
                            Positioned.fill(
                              child: _InteractiveCropOverlay(
                                rect: _cropRect,
                                imageAspect: imgAspect,
                                fixedAspect: _cropAspect,
                                onChanged: (next) =>
                                    setState(() => _cropRect = next),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // Miniaturas quando houver múltiplas fotos na fila
            if (_docs.length > 1)
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final selected = index == _activeIndex;
                    return GestureDetector(
                      onTap: () => _switchPhoto(index),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppColors.emeraldBright
                                : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: RawImage(
                            image: _docs[index].baseImage,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Legenda + botão grande de enviar no rodapé
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              color: Colors.black.withValues(alpha: 0.72),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _captionController,
                    maxLength: AppConstants.maxMessageLength,
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (v) => _currentDoc.caption = v,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: widget.captionHint,
                      hintStyle: const TextStyle(color: Colors.white60),
                      filled: true,
                      fillColor: AppColors.darkSurfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _exportAndReturn,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _exporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _exporting ? 'Preparando...' : primaryButtonLabel,
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
          ],
        ),
      ),
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  const _EditorToolButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.emerald
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _CropChip extends StatelessWidget {
  const _CropChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        selected: selected,
        selectedColor: AppColors.emerald,
        backgroundColor: AppColors.darkSurfaceAlt,
        side: BorderSide(
          color: selected ? AppColors.emeraldBright : Colors.white24,
        ),
        showCheckmark: false,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _CanvasStrokesPainter extends CustomPainter {
  const _CanvasStrokesPainter({
    required this.strokes,
    required this.activeStroke,
  });

  final List<_DrawStroke> strokes;
  final _DrawStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [
      ...strokes,
      if (activeStroke != null) activeStroke!,
    ];

    for (final stroke in all) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = (stroke.widthFraction * size.width).clamp(2.0, 22.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        final pt = Offset(
          stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height,
        );
        canvas.drawCircle(
          pt,
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      } else {
        final path = Path()
          ..moveTo(
            stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height,
          );
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(
            stroke.points[i].dx * size.width,
            stroke.points[i].dy * size.height,
          );
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasStrokesPainter oldDelegate) => true;
}

class _InteractiveCropOverlay extends StatelessWidget {
  const _InteractiveCropOverlay({
    required this.rect,
    required this.imageAspect,
    required this.fixedAspect,
    required this.onChanged,
  });

  final Rect rect; // normalizado 0..1
  final double imageAspect;
  final double? fixedAspect;
  final ValueChanged<Rect> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final pxRect = Rect.fromLTWH(
          rect.left * w,
          rect.top * h,
          rect.width * w,
          rect.height * h,
        );

        void moveCrop(DragUpdateDetails d) {
          final dx = d.delta.dx / w;
          final dy = d.delta.dy / h;
          final newLeft = (rect.left + dx).clamp(0.0, 1.0 - rect.width);
          final newTop = (rect.top + dy).clamp(0.0, 1.0 - rect.height);
          onChanged(Rect.fromLTWH(newLeft, newTop, rect.width, rect.height));
        }

        void dragCorner({
          required bool leftSide,
          required bool topSide,
          required DragUpdateDetails d,
        }) {
          final dx = d.delta.dx / w;
          final dy = d.delta.dy / h;
          var l = rect.left;
          var t = rect.top;
          var r = rect.right;
          var b = rect.bottom;

          if (leftSide) {
            l = (l + dx).clamp(0.0, r - 0.18);
          } else {
            r = (r + dx).clamp(l + 0.18, 1.0);
          }

          if (fixedAspect != null) {
            final normRatio = fixedAspect! / imageAspect;
            final newW = r - l;
            var newH = newW / normRatio;
            if (newH < 0.15) newH = 0.15;
            if (topSide) {
              t = (b - newH).clamp(0.0, b - 0.15);
            } else {
              b = (t + newH).clamp(t + 0.15, 1.0);
            }
          } else {
            if (topSide) {
              t = (t + dy).clamp(0.0, b - 0.15);
            } else {
              b = (b + dy).clamp(t + 0.15, 1.0);
            }
          }
          onChanged(Rect.fromLTRB(l, t, r, b));
        }

        return Stack(
          children: [
            // Máscara escura fora do recorte
            Positioned.fill(
              child: CustomPaint(
                painter: _CropMaskPainter(cropRect: pxRect),
              ),
            ),
            // Área central arrastável
            Positioned.fromRect(
              rect: pxRect,
              child: GestureDetector(
                onPanUpdate: moveCrop,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            // Alças dos 4 cantos
            _CropHandle(
              left: pxRect.left - 14,
              top: pxRect.top - 14,
              onDrag: (d) => dragCorner(leftSide: true, topSide: true, d: d),
            ),
            _CropHandle(
              left: pxRect.right - 14,
              top: pxRect.top - 14,
              onDrag: (d) => dragCorner(leftSide: false, topSide: true, d: d),
            ),
            _CropHandle(
              left: pxRect.left - 14,
              top: pxRect.bottom - 14,
              onDrag: (d) => dragCorner(leftSide: true, topSide: false, d: d),
            ),
            _CropHandle(
              left: pxRect.right - 14,
              top: pxRect.bottom - 14,
              onDrag: (d) => dragCorner(leftSide: false, topSide: false, d: d),
            ),
          ],
        );
      },
    );
  }
}

class _CropHandle extends StatelessWidget {
  const _CropHandle({
    required this.left,
    required this.top,
    required this.onDrag,
  });

  final double left;
  final double top;
  final ValueChanged<DragUpdateDetails> onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: onDrag,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.emeraldBright,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  const _CropMaskPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(cropRect);
    final masked = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(masked, Paint()..color = Colors.black.withValues(alpha: 0.6));

    // Linhas de regra dos terços
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 2; i++) {
      final x = cropRect.left + cropRect.width * (i / 3);
      final y = cropRect.top + cropRect.height * (i / 3);
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

class _StickerPickerChoice {
  const _StickerPickerChoice.emoji(this.emoji) : sticker = null;
  const _StickerPickerChoice.sticker(this.sticker) : emoji = null;

  final String? emoji;
  final ZapiSticker? sticker;
}

class _EditorStickerSheet extends StatefulWidget {
  const _EditorStickerSheet({required this.customStickers});

  final List<ZapiSticker> customStickers;

  @override
  State<_EditorStickerSheet> createState() => _EditorStickerSheetState();
}

class _EditorStickerSheetState extends State<_EditorStickerSheet> {
  int _tab = 0; // 0 = Emojis, 1 = Minhas figurinhas
  int _catIdx = 0;
  String? _skinTone;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final cats = UnicodeEmojiCatalog.categories;
    final query = _search.trim().toLowerCase();
    final filteredEmojis = query.isEmpty
        ? cats[_catIdx].items
        : cats
            .expand((c) => c.items)
            .where((e) => e.keywords.toLowerCase().contains(query))
            .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppColors.darkSurfaceAlt,
                      foregroundColor: Colors.white70,
                      selectedBackgroundColor: AppColors.emerald,
                      selectedForegroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.sentiment_satisfied_alt_rounded, size: 17),
                        label: Text('Emojis'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.sticky_note_2_rounded, size: 17),
                        label: Text('Figurinhas'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
              ],
            ),
          ),
          if (_tab == 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar emoji...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white54,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.darkSurfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String?>(
                    tooltip: 'Tom de pele',
                    onSelected: (tone) => setState(() => _skinTone = tone),
                    itemBuilder: (_) => [
                      for (final t in UnicodeEmojiCatalog.skinTones)
                        PopupMenuItem<String?>(
                          value: t.modifier,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: t.swatch,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(t.label),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: UnicodeEmojiCatalog.skinTones
                            .firstWhere(
                              (t) => t.modifier == _skinTone,
                              orElse: () => UnicodeEmojiCatalog.skinTones.first,
                            )
                            .swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (query.isEmpty)
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: cats.length,
                  itemBuilder: (_, idx) {
                    final selected = idx == _catIdx;
                    return IconButton(
                      tooltip: cats[idx].title,
                      onPressed: () => setState(() => _catIdx = idx),
                      icon: Icon(
                        cats[idx].icon,
                        color: selected
                            ? AppColors.emeraldBright
                            : Colors.white54,
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: filteredEmojis.length,
                itemBuilder: (_, idx) {
                  final entry = filteredEmojis[idx];
                  final glyph = UnicodeEmojiCatalog.applySkinTone(
                    entry.emoji,
                    _skinTone,
                    supportsSkinTone: entry.supportsSkinTone,
                  );
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.pop(
                      context,
                      _StickerPickerChoice.emoji(glyph),
                    ),
                    child: Center(
                      child: Text(glyph, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            Expanded(
              child: widget.customStickers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Você ainda não criou figurinhas. Crie suas próprias figurinhas na conversa para usar por cima das fotos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemCount: widget.customStickers.length,
                      itemBuilder: (_, idx) {
                        final sticker = widget.customStickers[idx];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(
                            context,
                            _StickerPickerChoice.sticker(sticker),
                          ),
                          child: ZapiStickerImage(
                            dataBase64: sticker.dataBase64,
                            mimeType: sticker.mimeType ?? 'image/webp',
                            size: 72,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
