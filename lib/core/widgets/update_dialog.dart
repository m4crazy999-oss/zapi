import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_update_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_exceptions.dart';
import 'zapi_logo.dart';

/// Tela inteira obrigatória exibida quando existe uma nova versão publicada.
/// Bloqueia o uso do aplicativo até concluir a atualização.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.update,
    required this.updateService,
  });

  final AppReleaseUpdate update;
  final AppUpdateService updateService;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen>
    with WidgetsBindingObserver {
  bool _isDownloading = false;
  double _progress = 0.0;
  String? _downloadedApkPath;
  String? _errorMessage;
  bool _needsInstallPermission = false;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _needsInstallPermission &&
        _downloadedApkPath != null) {
      unawaited(_retryOpenAfterPermission());
    }
  }

  Future<void> _retryOpenAfterPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (!mounted) return;
    if (status.isGranted && _downloadedApkPath != null) {
      setState(() {
        _needsInstallPermission = false;
        _errorMessage = null;
      });
      await _launchInstaller(_downloadedApkPath!);
    }
  }

  Future<void> _startUpdateFlow() async {
    if (_isDownloading) return;

    if (_downloadedApkPath != null) {
      await _ensurePermissionAndInstall(_downloadedApkPath!);
      return;
    }

    final cancelToken = CancelToken();
    setState(() {
      _cancelToken = cancelToken;
      _isDownloading = true;
      _progress = 0.0;
      _errorMessage = null;
      _needsInstallPermission = false;
    });

    try {
      final path = await widget.updateService.downloadApk(
        update: widget.update,
        cancelToken: cancelToken,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _progress = 1.0;
        _downloadedApkPath = path;
      });
      await _ensurePermissionAndInstall(path);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = e.message;
      });
    }
  }

  Future<void> _ensurePermissionAndInstall(String apkPath) async {
    var status = await Permission.requestInstallPackages.status;
    if (!status.isGranted) {
      if (!mounted) return;
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permitir instalação'),
          content: const Text(
            'Para instalar a atualização do Zapi diretamente por aqui, autorize a instalação nas configurações do aparelho.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );

      if (shouldRequest != true || !mounted) {
        setState(() {
          _needsInstallPermission = true;
          _errorMessage =
              'Autorize a permissão de instalação para concluir a atualização.';
        });
        return;
      }

      status = await Permission.requestInstallPackages.request();
      if (!mounted) return;

      if (!status.isGranted) {
        setState(() {
          _needsInstallPermission = true;
          _errorMessage =
              'Autorize a instalação para o Zapi nas configurações e volte para continuar.';
        });
        return;
      }
    }

    await _launchInstaller(apkPath);
  }

  Future<void> _launchInstaller(String apkPath) async {
    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (!mounted) return;
    if (result.type != ResultType.done) {
      setState(() {
        _errorMessage =
            'Não foi possível abrir o instalador. Toque em "Instalar agora" para tentar novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final notes = widget.update.notes;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: ZapiLogo(size: 72)),
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emerald.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Versão ${widget.update.versionLabel}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.emeraldBright
                                  : AppColors.emeraldDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Nova atualização disponível',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Atualize o Zapi para continuar usando suas conversas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.update.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 14),
                            if (notes.isEmpty)
                              Text(
                                'Melhorias gerais de desempenho e estabilidade.',
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 13.5,
                                ),
                              )
                            else
                              ...notes.map((item) => _NoteRow(item: item)),
                          ],
                        ),
                      ),
                      if (_isDownloading) ...[
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress >= 0 ? _progress : null,
                            minHeight: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _progress >= 0
                              ? 'Baixando atualização... ${(_progress * 100).round()}%'
                              : 'Baixando atualização...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: secondaryText,
                          ),
                        ),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_needsInstallPermission) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: openAppSettings,
                                  icon: const Icon(
                                    Icons.settings_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Abrir configurações'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: FilledButton.icon(
                  onPressed: _isDownloading ? null : _startUpdateFlow,
                  icon: Icon(
                    _downloadedApkPath != null
                        ? Icons.install_mobile_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    _downloadedApkPath != null
                        ? 'Instalar agora'
                        : (_isDownloading
                            ? 'Baixando atualização...'
                            : 'Baixar e atualizar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.item});

  final UpdateNoteItem item;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String badge) = switch (item.type) {
      UpdateNoteType.added => (
          Icons.auto_awesome_rounded,
          AppColors.emerald,
          'Novo',
        ),
      UpdateNoteType.improved => (
          Icons.trending_up_rounded,
          const Color(0xFF0284C7),
          'Melhorado',
        ),
      UpdateNoteType.fixed => (
          Icons.build_circle_rounded,
          const Color(0xFFD97706),
          'Corrigido',
        ),
      UpdateNoteType.other => (
          Icons.check_circle_rounded,
          AppColors.emerald,
          '',
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.38,
                    ),
                children: [
                  if (badge.isNotEmpty)
                    TextSpan(
                      text: '$badge: ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  TextSpan(text: item.text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
