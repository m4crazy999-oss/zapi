import 'dart:io';

import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../utils/app_exceptions.dart';
import 'app_lock_service.dart';

class PickedDocumentFile {
  const PickedDocumentFile({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final String mimeType;
}

class TranscodedVideoResult {
  const TranscodedVideoResult({
    required this.path,
    required this.sizeBytes,
    required this.durationMs,
  });

  final String path;
  final int sizeBytes;
  final int durationMs;
}

class NativeVideoMetadata {
  const NativeVideoMetadata({
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final int durationMs;
  final int width;
  final int height;
}

class NativeMediaBridge {
  NativeMediaBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.zapi.chat/media_bridge');

  static Future<PickedDocumentFile?> pickDocument({
    int maxBytes = AppConstants.maxChatFileBytes,
  }) async {
    if (!Platform.isAndroid) {
      throw const AppException(
        'Escolha de arquivos disponível somente no aplicativo Android.',
      );
    }

    AppLockBridge.isPromptActive = true;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'pickDocument',
        {'maxBytes': maxBytes},
      );
      if (raw == null) return null;

      final tooLarge = raw['tooLarge'] as bool? ?? false;
      if (tooLarge) {
        throw const AppException(
          'Esse arquivo é grande demais. Escolha um arquivo menor.',
        );
      }

      final path = (raw['path'] as String?) ?? '';
      if (path.isEmpty) return null;

      return PickedDocumentFile(
        path: path,
        fileName: (raw['fileName'] as String?) ?? 'arquivo',
        sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
        mimeType: (raw['mimeType'] as String?) ?? 'application/octet-stream',
      );
    } on AppException {
      rethrow;
    } on PlatformException {
      throw const AppException('Não foi possível abrir o seletor de arquivos.');
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        AppLockBridge.isPromptActive = false;
      });
    }
  }

  static Future<NativeVideoMetadata?> getVideoInfo(String path) async {
    if (!Platform.isAndroid || path.isEmpty) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getVideoInfo',
        {'path': path},
      );
      if (raw == null) return null;
      return NativeVideoMetadata(
        durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
        width: (raw['width'] as num?)?.toInt() ?? 0,
        height: (raw['height'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<TranscodedVideoResult> trimAndCompressVideo({
    required String inputPath,
    required int startMs,
    required int endMs,
    int maxBytes = AppConstants.maxStatusVideoBytes,
  }) async {
    if (!Platform.isAndroid) {
      throw const AppException(
        'Preparação de vídeo disponível somente no aplicativo Android.',
      );
    }

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'trimAndCompressVideo',
        {
          'inputPath': inputPath,
          'startMs': startMs,
          'endMs': endMs,
          'maxBytes': maxBytes,
        },
      );
      if (raw == null) {
        throw const AppException('Não foi possível preparar este vídeo.');
      }

      final tooLarge = raw['tooLarge'] as bool? ?? false;
      if (tooLarge) {
        throw const AppException(
          'Esse vídeo ficou pesado demais. Corte um trecho menor.',
        );
      }

      final outPath = (raw['path'] as String?) ?? '';
      if (outPath.isEmpty) {
        throw const AppException('Não foi possível salvar o vídeo recortado.');
      }

      return TranscodedVideoResult(
        path: outPath,
        sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
        durationMs: (raw['durationMs'] as num?)?.toInt() ?? (endMs - startMs),
      );
    } on AppException {
      rethrow;
    } on PlatformException {
      throw const AppException('Não foi possível preparar este vídeo.');
    }
  }
}
