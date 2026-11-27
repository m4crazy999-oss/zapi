import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'app_exceptions.dart';

class ProcessedImageResult {
  const ProcessedImageResult({
    required this.imagePath,
    required this.thumbnailPath,
    required this.imageBytes,
    required this.thumbnailBytes,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  final String imagePath;
  final String thumbnailPath;
  final Uint8List imageBytes;
  final Uint8List thumbnailBytes;
  final int width;
  final int height;
  final int sizeBytes;
}

class ProcessedStickerResult {
  const ProcessedStickerResult({
    required this.filePath,
    required this.bytes,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String filePath;
  final Uint8List bytes;
  final int sizeBytes;
  final String mimeType;
}

class MediaProcessor {
  MediaProcessor._();

  static const _uuid = Uuid();

  /// Comprime foto para lado maior <= 1280 px, ajusta qualidade automaticamente
  /// para ficar abaixo de 700 KB (seguro para o limite de 1 MiB do Firestore em base64)
  /// e gera miniatura abaixo de 20 KB, removendo todos os metadados EXIF.
  static Future<ProcessedImageResult> prepareChatPhoto(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const AppException('Arquivo de imagem não encontrado.');
    }

    final rawBytes = await sourceFile.readAsBytes();
    final tempDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tempDir.path, 'zapi_media_out'));
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final id = _uuid.v4();
    final mainPath = p.join(outDir.path, '${id}_full.jpg');
    final thumbPath = p.join(outDir.path, '${id}_thumb.jpg');

    final encoded = await Isolate.run(() => _encodeImagePairInIsolate(rawBytes));
    if (encoded == null) {
      throw const AppException(
        'Não foi possível processar esta imagem. Tente outro arquivo.',
      );
    }

    if (encoded.mainBytes.length > AppConstants.maxChatImageBytes ||
        base64Encode(encoded.mainBytes).length >
            AppConstants.maxFirestoreMediaBase64Chars) {
      throw const AppException(
        'A foto é muito grande, tente escolher outra.',
      );
    }

    if (encoded.thumbBytes.length > AppConstants.maxThumbnailBytes) {
      throw const AppException(
        'Não foi possível preparar esta foto. Tente outra imagem.',
      );
    }

    await File(mainPath).writeAsBytes(encoded.mainBytes, flush: true);
    await File(thumbPath).writeAsBytes(encoded.thumbBytes, flush: true);

    return ProcessedImageResult(
      imagePath: mainPath,
      thumbnailPath: thumbPath,
      imageBytes: encoded.mainBytes,
      thumbnailBytes: encoded.thumbBytes,
      width: encoded.width,
      height: encoded.height,
      sizeBytes: encoded.mainBytes.length,
    );
  }

  /// Prepara imagem para Status respeitando o limite de 450 KB (compatível com Firestore gratuito).
  static Future<Uint8List> prepareStatusPhoto(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const AppException('Arquivo de imagem não encontrado.');
    }

    final rawBytes = await sourceFile.readAsBytes();
    final compressed = await Isolate.run(() => _encodeStatusImageInIsolate(rawBytes));
    if (compressed == null ||
        compressed.length > AppConstants.maxStatusImageBytes ||
        base64Encode(compressed).length > AppConstants.maxStatusImageBase64Chars) {
      throw const AppException(
        'A foto selecionada ficou pesada demais para o Status. Escolha outra imagem.',
      );
    }
    return compressed;
  }

  static Uint8List? _encodeStatusImageInIsolate(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    final baked = img.bakeOrientation(decoded);
    const maxSides = [1280, 1080, 920, 760, 620];
    const qualities = [80, 68, 56, 44, 32];

    for (var i = 0; i < maxSides.length; i++) {
      final resized = _resizeKeepingAspect(baked, maxSide: maxSides[i]);
      resized.exif.clear();
      final candidate = Uint8List.fromList(
        img.encodeJpg(resized, quality: qualities[i]),
      );
      if (candidate.length <= AppConstants.maxStatusImageBytes &&
          base64Encode(candidate).length <=
              AppConstants.maxStatusImageBase64Chars) {
        return candidate;
      }
    }
    return null;
  }

  /// Converte imagem recortada em figurinha WebP 512x512 abaixo de 100 KB,
  /// com transparência circular opcional.
  static Future<ProcessedStickerResult> prepareSticker(
    String sourcePath, {
    required bool circularTransparentMask,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const AppException('Imagem de origem não encontrada.');
    }

    final rawBytes = await sourceFile.readAsBytes();
    final tempDir = await getTemporaryDirectory();
    final id = _uuid.v4();
    final tempPngPath = p.join(tempDir.path, 'sticker_src_$id.png');
    final finalWebpPath = p.join(tempDir.path, 'sticker_$id.webp');

    final preparedPng = await Isolate.run(
      () => _prepareSquarePngInIsolate(
        rawBytes,
        circularMask: circularTransparentMask,
      ),
    );
    if (preparedPng == null) {
      throw const AppException(
        'Não foi possível converter esta imagem em figurinha.',
      );
    }

    await File(tempPngPath).writeAsBytes(preparedPng, flush: true);

    try {
      Uint8List? webpBytes;
      const qualities = [86, 74, 62, 48, 36, 24];
      const dimensions = [512, 512, 512, 512, 420, 360];

      for (var i = 0; i < qualities.length; i++) {
        final compressed = await FlutterImageCompress.compressWithFile(
          tempPngPath,
          minWidth: dimensions[i],
          minHeight: dimensions[i],
          quality: qualities[i],
          format: CompressFormat.webp,
        );
        if (compressed != null && compressed.isNotEmpty) {
          webpBytes = Uint8List.fromList(compressed);
          if (webpBytes.length <= AppConstants.maxStickerBytes) {
            break;
          }
        }
      }

      if (webpBytes == null ||
          webpBytes.isEmpty ||
          webpBytes.length > AppConstants.maxStickerBytes) {
        throw const AppException(
          'A figurinha ficou pesada demais. Escolha uma foto mais simples.',
        );
      }

      await File(finalWebpPath).writeAsBytes(webpBytes, flush: true);

      return ProcessedStickerResult(
        filePath: finalWebpPath,
        bytes: webpBytes,
        sizeBytes: webpBytes.length,
        mimeType: 'image/webp',
      );
    } finally {
      final pngFile = File(tempPngPath);
      if (await pngFile.exists()) {
        await pngFile.delete().catchError((_) => pngFile);
      }
    }
  }

  /// Detecta se os bytes representam um GIF ou WebP com múltiplos quadros.
  static Future<bool> isAnimatedImage(Uint8List rawBytes) async {
    return Isolate.run(() => _detectAnimatedInIsolate(rawBytes));
  }

  /// Redimensiona e comprime foto de perfil animada (GIF/WebP) para caber em 100 KB.
  static Future<Uint8List> compressAnimatedAvatarIfNeeded(
    Uint8List rawBytes,
  ) async {
    if (rawBytes.length <= AppConstants.maxProfilePhotoBytes) {
      return rawBytes;
    }
    final compressed = await Isolate.run(
      () => _compressAnimatedAvatarInIsolate(rawBytes),
    );
    if (compressed == null ||
        compressed.length > AppConstants.maxProfilePhotoBytes) {
      throw const AppException(
        'A imagem animada é muito pesada. Escolha um GIF ou WebP menor.',
      );
    }
    return compressed;
  }

  /// Redimensiona banner animado (GIF/WebP) para caber no limite de 320 KB.
  static Future<Uint8List> compressAnimatedBannerIfNeeded(
    Uint8List rawBytes,
  ) async {
    if (rawBytes.length <= AppConstants.maxProfileBannerBytes) {
      return rawBytes;
    }
    final compressed = await Isolate.run(
      () => _compressAnimatedBannerInIsolate(rawBytes),
    );
    if (compressed == null ||
        compressed.length > AppConstants.maxProfileBannerBytes) {
      throw const AppException(
        'Esse GIF é grande demais para o banner. Escolha um GIF mais curto ou leve.',
      );
    }
    return compressed;
  }

  static bool _detectAnimatedInIsolate(Uint8List rawBytes) {
    final gif = img.decodeGif(rawBytes);
    if (gif != null && gif.numFrames > 1) return true;
    final webp = img.decodeWebP(rawBytes);
    if (webp != null && webp.numFrames > 1) return true;
    return false;
  }

  static Uint8List? _compressAnimatedAvatarInIsolate(Uint8List rawBytes) {
    final decoded = img.decodeGif(rawBytes) ?? img.decodeWebP(rawBytes);
    if (decoded == null || decoded.numFrames <= 1) return null;

    const targetSides = [160, 128, 96, 80];
    const frameSteps = [1, 1, 2, 2];

    for (var attempt = 0; attempt < targetSides.length; attempt++) {
      final side = targetSides[attempt];
      final step = frameSteps[attempt];
      img.Image? out;

      for (var i = 0; i < decoded.frames.length; i += step) {
        final frame = decoded.frames[i];
        final cropped = img.copyResizeCropSquare(
          frame,
          size: side,
          interpolation: img.Interpolation.linear,
        );
        cropped.frameDuration = frame.frameDuration * step;
        if (out == null) {
          out = cropped;
        } else {
          out.addFrame(cropped);
        }
      }

      if (out == null) continue;
      final candidate = Uint8List.fromList(img.encodeGif(out));
      if (candidate.length <= AppConstants.maxProfilePhotoBytes) {
        return candidate;
      }
    }
    return null;
  }

  static Uint8List? _compressAnimatedBannerInIsolate(Uint8List rawBytes) {
    final decoded = img.decodeGif(rawBytes) ?? img.decodeWebP(rawBytes);
    if (decoded == null || decoded.numFrames <= 1) return null;

    const targetWidths = [420, 340, 260, 210];
    const frameSteps = [1, 2, 2, 3];

    for (var attempt = 0; attempt < targetWidths.length; attempt++) {
      final targetW = targetWidths[attempt];
      final step = frameSteps[attempt];
      img.Image? out;

      for (var i = 0; i < decoded.frames.length; i += step) {
        final frame = decoded.frames[i];
        final resized = img.copyResize(
          frame,
          width: math.min(targetW, frame.width),
          interpolation: img.Interpolation.linear,
        );
        resized.frameDuration = frame.frameDuration * step;
        if (out == null) {
          out = resized;
        } else {
          out.addFrame(resized);
        }
      }

      if (out == null) continue;
      final candidate = Uint8List.fromList(img.encodeGif(out));
      if (candidate.length <= AppConstants.maxProfileBannerBytes) {
        return candidate;
      }
    }
    return null;
  }

  static _EncodedPair? _encodeImagePairInIsolate(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    // Aplica orientação EXIF nos pixels antes de descartar metadados EXIF.
    final baked = img.bakeOrientation(decoded);

    const maxSides = [1280, 1280, 1280, 1080, 960, 800, 640];
    const qualities = [82, 70, 58, 52, 44, 36, 28];

    late img.Image chosenImage;
    late Uint8List mainBytes;

    for (var i = 0; i < maxSides.length; i++) {
      final resized = _resizeKeepingAspect(baked, maxSide: maxSides[i]);
      resized.exif.clear();
      final candidate = Uint8List.fromList(
        img.encodeJpg(resized, quality: qualities[i]),
      );
      chosenImage = resized;
      mainBytes = candidate;
      if (candidate.length <= AppConstants.maxChatImageBytes) {
        break;
      }
    }

    // Gera miniatura nítida (<= 26 KB) para exibição imediata sem borrão na conversa.
    const thumbSides = [320, 260, 200, 140];
    const thumbQualities = [72, 60, 48, 34];
    late Uint8List thumbBytes;

    for (var i = 0; i < thumbSides.length; i++) {
      final thumbImage = _resizeKeepingAspect(
        chosenImage,
        maxSide: thumbSides[i],
      );
      thumbImage.exif.clear();
      final candidateThumb = Uint8List.fromList(
        img.encodeJpg(thumbImage, quality: thumbQualities[i]),
      );
      thumbBytes = candidateThumb;
      if (candidateThumb.length <= AppConstants.maxThumbnailBytes) {
        break;
      }
    }

    return _EncodedPair(
      mainBytes: mainBytes,
      thumbBytes: thumbBytes,
      width: chosenImage.width,
      height: chosenImage.height,
    );
  }

  static Uint8List? _prepareSquarePngInIsolate(
    Uint8List rawBytes, {
    required bool circularMask,
  }) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return null;

    final baked = img.bakeOrientation(decoded);
    var square = img.copyResizeCropSquare(
      baked,
      size: AppConstants.stickerSizePx,
      interpolation: img.Interpolation.linear,
    );
    square.exif.clear();

    if (circularMask) {
      square = _applyCircularAlphaMask(square);
    }

    return Uint8List.fromList(img.encodePng(square, level: 4));
  }

  static img.Image _resizeKeepingAspect(
    img.Image source, {
    required int maxSide,
  }) {
    final width = source.width;
    final height = source.height;
    final currentMax = math.max(width, height);
    if (currentMax <= maxSide) {
      return source.clone();
    }

    final scale = maxSide / currentMax;
    final newW = math.max(1, (width * scale).round());
    final newH = math.max(1, (height * scale).round());

    return img.copyResize(
      source,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.linear,
    );
  }

  static img.Image _applyCircularAlphaMask(img.Image source) {
    final size = source.width;
    final out = img.Image(
      width: size,
      height: size,
      numChannels: 4,
    );

    final center = (size - 1) / 2.0;
    final radius = size * 0.485;
    const feather = 2.0;

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final dx = x - center;
        final dy = y - center;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= radius + feather) {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final pixel = source.getPixel(x, y);
        var alpha = pixel.a.toDouble();
        if (dist > radius - feather) {
          final t = 1.0 - ((dist - (radius - feather)) / (2.0 * feather));
          alpha *= t.clamp(0.0, 1.0);
        }
        out.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          alpha.round().clamp(0, 255),
        );
      }
    }

    return out;
  }
}

class _EncodedPair {
  const _EncodedPair({
    required this.mainBytes,
    required this.thumbBytes,
    required this.width,
    required this.height,
  });

  final Uint8List mainBytes;
  final Uint8List thumbBytes;
  final int width;
  final int height;
}
