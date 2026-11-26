import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import 'app_exceptions.dart';

class ImageHelper {
  ImageHelper._();

  static final ImagePicker _picker = ImagePicker();

  /// Seleciona foto (câmera ou galeria), recorta em 1:1 e comprime para <= 256x256
  /// em WebP/JPEG abaixo de 100 KB para armazenamento direto em base64 no Firestore.
  static Future<Uint8List?> pickCropAndCompressAvatar(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: AppConstants.maxProfilePhotoDimension,
      maxHeight: AppConstants.maxProfilePhotoDimension,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar foto',
          toolbarColor: AppColors.emerald,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppColors.emerald,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
      ],
    );
    if (cropped == null) return null;

    try {
      return await _compressAvatarUnderLimit(File(cropped.path));
    } finally {
      final croppedFile = File(cropped.path);
      if (await croppedFile.exists()) {
        await croppedFile.delete().catchError((_) => croppedFile);
      }
    }
  }

  static Future<Uint8List> _compressAvatarUnderLimit(File sourceFile) async {
    const qualities = [82, 70, 58, 45, 34, 24];
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
      'Não foi possível comprimir a foto de perfil abaixo de 100 KB. Escolha outra imagem.',
    );
  }
}
