import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_exceptions.dart';

enum UpdateNoteType {
  added,
  improved,
  fixed,
  other,
}

class UpdateNoteItem {
  const UpdateNoteItem({
    required this.type,
    required this.text,
  });

  final UpdateNoteType type;
  final String text;
}

class AppReleaseUpdate {
  const AppReleaseUpdate({
    required this.versionLabel,
    required this.remoteBuildNumber,
    required this.currentBuildNumber,
    required this.currentVersionLabel,
    required this.title,
    required this.notes,
    required this.apkDownloadUrl,
    required this.apkFileName,
  });

  final String versionLabel;
  final int remoteBuildNumber;
  final int currentBuildNumber;
  final String currentVersionLabel;
  final String title;
  final List<UpdateNoteItem> notes;
  final String apkDownloadUrl;
  final String apkFileName;
}

class AppUpdateService {
  AppUpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(minutes: 4),
                sendTimeout: const Duration(seconds: 12),
              ),
            );

  static const String _latestReleaseEndpoint =
      'https://api.github.com/repos/m4crazy999-oss/zapi/releases/latest';

  final Dio _dio;
  bool _isChecking = false;

  Future<String> getInstalledVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    if (info.buildNumber.isNotEmpty) {
      return '${info.version} (${info.buildNumber})';
    }
    return info.version;
  }

  /// Verifica imediatamente na abertura e no retorno ao primeiro plano se há
  /// uma versão mais nova publicada no repositório.
  Future<AppReleaseUpdate?> checkForUpdate({bool throwOnError = false}) async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
      final currentVersionLabel = packageInfo.version.trim().isNotEmpty
          ? packageInfo.version.trim()
          : '1.0.$currentBuild';

      final cacheBuster = DateTime.now().millisecondsSinceEpoch;
      final response = await _dio.get<Map<String, dynamic>>(
        '$_latestReleaseEndpoint?t=$cacheBuster',
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'Cache-Control': 'no-cache, no-store',
            'Pragma': 'no-cache',
            'User-Agent': 'Zapi-Android-App',
          },
        ),
      );

      final data = response.data;
      if (data == null) return null;

      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final remoteBuild = _extractBuildNumber(tagName);
      if (remoteBuild == null || remoteBuild <= currentBuild) {
        return null;
      }

      final assets = data['assets'];
      String? apkUrl;
      String apkName = 'zapi-$tagName.apk';

      if (assets is List) {
        for (final rawAsset in assets) {
          if (rawAsset is! Map) continue;
          final name = (rawAsset['name'] as String?)?.trim() ?? '';
          final url = (rawAsset['browser_download_url'] as String?)?.trim() ?? '';
          if (name.toLowerCase().endsWith('.apk') && _isSafeHttpsUrl(url)) {
            apkUrl = url;
            apkName = name;
            break;
          }
        }
      }

      if (apkUrl == null) {
        return null;
      }

      final body = (data['body'] as String?) ?? '';
      final parsed = _parseReleaseBody(body);

      return AppReleaseUpdate(
        versionLabel: _formatVersionLabel(tagName),
        remoteBuildNumber: remoteBuild,
        currentBuildNumber: currentBuild,
        currentVersionLabel: currentVersionLabel,
        title: parsed.title,
        notes: parsed.notes,
        apkDownloadUrl: apkUrl,
        apkFileName: _sanitizeFileName(apkName),
      );
    } catch (_) {
      if (throwOnError) {
        throw const AppException(
          'Não foi possível verificar atualizações agora. Verifique sua conexão e tente novamente.',
        );
      }
      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// Baixa o arquivo de atualização para a pasta temporária do app.
  Future<String> downloadApk({
    required AppReleaseUpdate update,
    required void Function(double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!_isSafeHttpsUrl(update.apkDownloadUrl)) {
      throw const AppException('Endereço de atualização inválido.');
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final updatesDir = Directory(p.join(tempDir.path, 'zapi_updates'));
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final targetPath = p.join(updatesDir.path, update.apkFileName);
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await _dio.download(
        update.apkDownloadUrl,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          } else {
            onProgress(-1);
          }
        },
      );

      if (!await targetFile.exists() || await targetFile.length() == 0) {
        throw const AppException('O arquivo de atualização veio vazio.');
      }

      return targetPath;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const AppException('Download da atualização cancelado.');
      }
      throw const AppException(
        'Não foi possível baixar a atualização. Verifique sua conexão e tente novamente.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw const AppException(
        'Não foi possível baixar a atualização. Tente novamente em instantes.',
      );
    }
  }

  int? _extractBuildNumber(String tagName) {
    final match = RegExp(r'(\d+)$').firstMatch(tagName);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String _formatVersionLabel(String tagName) {
    final clean = tagName.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      return clean.substring(1);
    }
    return clean;
  }

  bool _isSafeHttpsUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  String _sanitizeFileName(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return clean.toLowerCase().endsWith('.apk') ? clean : '$clean.apk';
  }

  _ParsedReleaseNotes _parseReleaseBody(String rawBody) {
    final lines = rawBody.split(RegExp(r'\r?\n'));
    String? title;
    final notes = <UpdateNoteItem>[];

    final mandatoryRegex = RegExp(
      r'^OBRIGAT[ÓO]RIA\s*:\s*sim\b',
      caseSensitive: false,
    );

    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (mandatoryRegex.hasMatch(line)) continue;

      final isBullet = line.startsWith('- ') || line.startsWith('* ');
      if (!isBullet && title == null) {
        line = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (line.isNotEmpty) {
          title = line;
        }
        continue;
      }

      final content = isBullet ? line.substring(2).trim() : line;
      if (content.isEmpty) continue;

      notes.add(_classifyNote(content));
    }

    return _ParsedReleaseNotes(
      title: title ?? 'Novidades e melhorias no Zapi',
      notes: notes,
    );
  }

  UpdateNoteItem _classifyNote(String line) {
    final lower = line.toLowerCase();
    if (lower.startsWith('novo:')) {
      return UpdateNoteItem(
        type: UpdateNoteType.added,
        text: line.substring(5).trim(),
      );
    }
    if (lower.startsWith('melhorado:')) {
      return UpdateNoteItem(
        type: UpdateNoteType.improved,
        text: line.substring(10).trim(),
      );
    }
    if (lower.startsWith('corrigido:')) {
      return UpdateNoteItem(
        type: UpdateNoteType.fixed,
        text: line.substring(10).trim(),
      );
    }
    return UpdateNoteItem(type: UpdateNoteType.other, text: line);
  }
}

class _ParsedReleaseNotes {
  const _ParsedReleaseNotes({
    required this.title,
    required this.notes,
  });

  final String title;
  final List<UpdateNoteItem> notes;
}

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

final appVersionLabelProvider = FutureProvider<String>((ref) async {
  return ref.watch(appUpdateServiceProvider).getInstalledVersionLabel();
});
