import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../features/profile/presentation/screens/avatar_crop_screen.dart';
import '../constants/app_constants.dart';
import '../services/app_lock_service.dart';
import 'app_exceptions.dart';
import 'media_processor.dart';

class ImageHelper {
  ImageHelper._();

  static final ImagePicker _picker = ImagePicker();
  static const _uuid = Uuid();

  static Future<XFile?> _pickImageGuarded({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    AppLockBridge.isPromptActive = true;
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        AppLockBridge.isPromptActive = false;
      });
    }
  }

  /// Seleciona foto (estática ou animada GIF/WebP), abre tela de confirmação
  /// com botão inferior acessível e garante <= 100 KB em base64.
  static Future<Uint8List?> pickCropAndCompressAvatar(
    BuildContext context,
    ImageSource source,
  ) async {
    final picked = source == ImageSource.camera
        ? await _pickImageGuarded(
            source: source,
            maxWidth: 1280,
            maxHeight: 1280,
            imageQuality: 92,
          )
        : await _pickImageGuarded(source: source);
    if (picked == null || !context.mounted) return null;

    final rawBytes = await File(picked.path).readAsBytes();
    final isAnimated = await MediaProcessor.isAnimatedImage(rawBytes);
    if (!context.mounted) return null;

    if (isAnimated) {
      final preparedAnim =
          await MediaProcessor.compressAnimatedAvatarIfNeeded(rawBytes);
      if (!context.mounted) return null;
      return AvatarCropScreen.open(
        context,
        imageBytes: preparedAnim,
        title: 'Foto animada',
        confirmLabel: 'Confirmar foto',
        circularOverlay: true,
        isAnimated: true,
      );
    }

    final croppedBytes = await AvatarCropScreen.open(
      context,
      imageBytes: rawBytes,
      title: 'Ajustar foto de perfil',
      confirmLabel: 'Confirmar foto',
      circularOverlay: true,
    );
    if (croppedBytes == null) return null;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'avatar_${_uuid.v4()}.png'));
    try {
      await tempFile.writeAsBytes(croppedBytes, flush: true);
      return await _compressAvatarUnderLimit(tempFile);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile);
      }
    }
  }

  /// Seleciona e recorta imagem quadrada usando a tela própria com botão inferior.
  static Future<String?> pickAndCropSquareImage(
    BuildContext context,
    ImageSource source, {
    String title = 'Recortar figurinha',
  }) async {
    final picked = await _pickImageGuarded(source: source);
    if (picked == null || !context.mounted) return null;

    final rawBytes = await File(picked.path).readAsBytes();
    if (!context.mounted) return null;

    final croppedBytes = await AvatarCropScreen.open(
      context,
      imageBytes: rawBytes,
      title: title,
      confirmLabel: 'Confirmar recorte',
      circularOverlay: false,
    );
    if (croppedBytes == null) return null;

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'crop_${_uuid.v4()}.png');
    await File(outPath).writeAsBytes(croppedBytes, flush: true);
    return outPath;
  }

  static Future<Uint8List> _compressAvatarUnderLimit(File sourceFile) async {
    const qualities = [84, 72, 60, 46, 34, 24];
    const dimensions = [256, 256, 256, 224, 192, 160];

    for (var i = 0; i < qualities.length; i++) {
      final webpBytes = await FlutterImageCompress.compressWithFile(
        sourceFile.absolute.path,
        quality: qualities[i],
        minWidth: dimensions[i],
        minHeight: dimensions[i],
        format: CompressFormat.webp,
      );
      if (webpBytes != null &&
          webpBytes.isNotEmpty &&
          webpBytes.length <= AppConstants.maxProfilePhotoBytes) {
        return Uint8List.fromList(webpBytes);
      }

      final jpegBytes = await FlutterImageCompress.compressWithFile(
        sourceFile.absolute.path,
        quality: qualities[i],
        minWidth: dimensions[i],
        minHeight: dimensions[i],
        format: CompressFormat.jpeg,
      );
      if (jpegBytes != null &&
          jpegBytes.isNotEmpty &&
          jpegBytes.length <= AppConstants.maxProfilePhotoBytes) {
        return Uint8List.fromList(jpegBytes);
      }
    }

    throw const AppException(
      'A foto selecionada é muito grande. Tente escolher outra imagem.',
    );
  }

  /// Seleciona imagem estática ou GIF animado da galeria para o banner,
  /// comprime respeitando o limite de 320 KB e abre confirmação em tela cheia.
  static Future<Uint8List?> pickCropAndCompressBanner(
    BuildContext context,
  ) async {
    final picked = await _pickImageGuarded(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return null;

    final rawBytes = await File(picked.path).readAsBytes();
    final isAnimated = await MediaProcessor.isAnimatedImage(rawBytes);
    if (!context.mounted) return null;

    if (isAnimated) {
      final preparedAnim =
          await MediaProcessor.compressAnimatedBannerIfNeeded(rawBytes);
      if (!context.mounted) return null;
      return AvatarCropScreen.open(
        context,
        imageBytes: preparedAnim,
        title: 'Banner animado',
        confirmLabel: 'Confirmar banner',
        circularOverlay: false,
        isAnimated: true,
        aspectRatio: 16 / 10,
      );
    }

    final croppedBytes = await AvatarCropScreen.open(
      context,
      imageBytes: rawBytes,
      title: 'Ajustar banner',
      confirmLabel: 'Confirmar banner',
      circularOverlay: false,
      aspectRatio: 16 / 10,
    );
    if (croppedBytes == null) return null;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'banner_${_uuid.v4()}.png'));
    try {
      await tempFile.writeAsBytes(croppedBytes, flush: true);
      return await _compressBannerUnderLimit(tempFile);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete().catchError((_) => tempFile);
      }
    }
  }

  static Future<Uint8List> _compressBannerUnderLimit(File sourceFile) async {
    const qualities = [86, 76, 66, 54, 42, 32];
    const widths = [960, 960, 840, 720, 640, 540];

    for (var i = 0; i < qualities.length; i++) {
      final w = widths[i];
      final h = (w * 10 / 16).round();

      final webpBytes = await FlutterImageCompress.compressWithFile(
        sourceFile.absolute.path,
        quality: qualities[i],
        minWidth: w,
        minHeight: h,
        format: CompressFormat.webp,
      );
      if (webpBytes != null &&
          webpBytes.isNotEmpty &&
          webpBytes.length <= AppConstants.maxProfileBannerBytes) {
        return Uint8List.fromList(webpBytes);
      }

      final jpegBytes = await FlutterImageCompress.compressWithFile(
        sourceFile.absolute.path,
        quality: qualities[i],
        minWidth: w,
        minHeight: h,
        format: CompressFormat.jpeg,
      );
      if (jpegBytes != null &&
          jpegBytes.isNotEmpty &&
          jpegBytes.length <= AppConstants.maxProfileBannerBytes) {
        return Uint8List.fromList(jpegBytes);
      }
    }

    throw const AppException(
      'A imagem selecionada ficou grande demais para o banner. Tente escolher outra.',
    );
  }
}
