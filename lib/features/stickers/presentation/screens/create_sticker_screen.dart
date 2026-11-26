import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/media_processor.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/stickers_providers.dart';

class CreateStickerScreen extends ConsumerStatefulWidget {
  const CreateStickerScreen({super.key});

  @override
  ConsumerState<CreateStickerScreen> createState() =>
      _CreateStickerScreenState();
}

class _CreateStickerScreenState extends ConsumerState<CreateStickerScreen> {
  final _picker = ImagePicker();
  String? _croppedSourcePath;
  Uint8List? _previewPngBytes;
  bool _circularMask = true;
  bool _isProcessing = false;
  bool _isSaving = false;

  Future<void> _pickAndCrop(ImageSource source) async {
    final hasPermission = source == ImageSource.camera
        ? await PermissionHelper.requestCamera(context)
        : await PermissionHelper.requestGallery(context);
    if (!hasPermission || !mounted) return;

    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar figurinha',
            toolbarColor: AppColors.emeraldDark,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.emerald,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
        ],
      );

      if (cropped == null || !mounted) return;

      _croppedSourcePath = cropped.path;
      await _renderStickerPreview();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AppException
                ? error.message
                : 'Não foi possível preparar a imagem selecionada.',
          ),
        ),
      );
    }
  }

  Future<void> _renderStickerPreview() async {
    final sourcePath = _croppedSourcePath;
    if (sourcePath == null) return;

    setState(() => _isProcessing = true);
    try {
      final processed = await MediaProcessor.prepareSticker(
        sourcePath,
        circularTransparentMask: _circularMask,
      );
      if (!mounted) return;
      setState(() {
        _previewPngBytes = processed.bytes;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveSticker() async {
    final bytes = _previewPngBytes;
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    if (bytes == null || uid.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final sticker = await ref
          .read(stickersRepositoryProvider)
          .createCustomSticker(uid: uid, webpBytes: bytes);
      if (!mounted) return;
      Navigator.pop(context, sticker);
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar figurinha'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: _CheckerboardPainter(isDark: isDark),
                child: Center(
                  child: _isProcessing
                      ? const CircularProgressIndicator()
                      : (_previewPngBytes != null
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: Image.memory(
                                _previewPngBytes!,
                                fit: BoxFit.contain,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_reaction_outlined,
                                  size: 48,
                                  color: secondaryText,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Escolha uma foto\npara recortar (512×512)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing || _isSaving
                      ? null
                      : () => _pickAndCrop(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galeria'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing || _isSaving
                      ? null
                      : () => _pickAndCrop(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Câmera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _circularMask,
            title: const Text('Recorte circular com bordas transparentes'),
            subtitle: const Text(
              'Remove os cantos da foto em PNG transparente 512×512.',
            ),
            onChanged: _isProcessing || _isSaving
                ? null
                : (val) async {
                    setState(() => _circularMask = val);
                    if (_croppedSourcePath != null) {
                      await _renderStickerPreview();
                    }
                  },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: secondaryText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'O recorte roda direto no celular (WebP 512×512 até 100 KB), salvo no Firestore gratuito sem precisar do Storage.',
                    style: TextStyle(fontSize: 12.5, color: secondaryText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_previewPngBytes == null || _isProcessing || _isSaving)
                ? null
                : _saveSticker,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isSaving ? 'Salvando...' : 'Salvar figurinha'),
          ),
        ],
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 14.0;
    final c1 = Paint()
      ..color = isDark ? const Color(0xFF1A252B) : const Color(0xFFF0F4F3);
    final c2 = Paint()
      ..color = isDark ? const Color(0xFF222E35) : const Color(0xFFE3EAE8);

    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell, cell),
          (r + c).isEven ? c1 : c2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
