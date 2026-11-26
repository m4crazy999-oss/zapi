import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  PermissionHelper._();

  static Future<bool> requestCamera(BuildContext context) {
    return _requestWithRationale(
      context: context,
      permission: Permission.camera,
      title: 'Acesso à câmera',
      rationale:
          'O Zapi precisa usar a câmera apenas quando você escolhe tirar uma foto ou criar uma figurinha na hora.',
      deniedMessage:
          'Permissão de câmera negada. Sem ela não é possível tirar fotos.',
      permanentlyDeniedMessage:
          'A permissão da câmera foi bloqueada nas configurações do Android. Ative-a nas configurações do aplicativo para continuar.',
    );
  }

  static Future<bool> requestMicrophone(BuildContext context) {
    return _requestWithRationale(
      context: context,
      permission: Permission.microphone,
      title: 'Acesso ao microfone',
      rationale:
          'O Zapi precisa do microfone para gravar mensagens de voz quando você segura ou trava o botão de áudio.',
      deniedMessage:
          'Permissão de microfone negada. Sem ela não é possível gravar mensagens de voz.',
      permanentlyDeniedMessage:
          'O acesso ao microfone foi desativado permanentemente. Abra as configurações do Zapi no Android para liberar o microfone.',
    );
  }

  static Future<bool> requestGallery(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final photosStatus = await Permission.photos.status;
    if (photosStatus.isGranted || photosStatus.isLimited) {
      return true;
    }

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) {
      return true;
    }

    if (!context.mounted) return false;

    final shouldAsk = await _showRationaleDialog(
      context: context,
      title: 'Acesso às fotos',
      message:
          'O Zapi precisa acessar suas fotos apenas para você escolher imagens da galeria, criar figurinhas ou salvar fotos recebidas.',
      confirmLabel: 'Continuar',
    );
    if (!shouldAsk) return false;

    var result = await Permission.photos.request();
    if (result.isGranted || result.isLimited) {
      return true;
    }

    // Em aparelhos Android 12 ou inferiores, Permission.storage cobre READ_EXTERNAL_STORAGE.
    if (result.isDenied) {
      final legacyResult = await Permission.storage.request();
      if (legacyResult.isGranted) return true;
      if (legacyResult.isPermanentlyDenied) {
        result = legacyResult;
      }
    }

    if (!context.mounted) return false;

    if (result.isPermanentlyDenied || result.isRestricted) {
      await _showOpenSettingsDialog(
        context: context,
        title: 'Permissão necessária',
        message:
            'O acesso à galeria foi bloqueado. Abra as configurações do aplicativo no Android e permita o acesso a fotos e mídia.',
      );
      return false;
    }

    _showSnack(
      context,
      'Permissão da galeria negada. Você pode liberar quando quiser.',
    );
    return false;
  }

  static Future<bool> _requestWithRationale({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String rationale,
    required String deniedMessage,
    required String permanentlyDeniedMessage,
  }) async {
    final current = await permission.status;
    if (current.isGranted || current.isLimited) {
      return true;
    }

    if (current.isPermanentlyDenied) {
      if (!context.mounted) return false;
      await _showOpenSettingsDialog(
        context: context,
        title: title,
        message: permanentlyDeniedMessage,
      );
      return false;
    }

    if (current.isDenied) {
      if (!context.mounted) return false;
      final proceed = await _showRationaleDialog(
        context: context,
        title: title,
        message: rationale,
        confirmLabel: 'Permitir',
      );
      if (!proceed) return false;
    }

    final result = await permission.request();
    if (result.isGranted || result.isLimited) {
      return true;
    }

    if (!context.mounted) return false;

    if (result.isPermanentlyDenied || result.isRestricted) {
      await _showOpenSettingsDialog(
        context: context,
        title: title,
        message: permanentlyDeniedMessage,
      );
      return false;
    }

    _showSnack(context, deniedMessage);
    return false;
  }

  static Future<bool> _showRationaleDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return approved ?? false;
  }

  static Future<void> _showOpenSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await openAppSettings();
              },
              child: const Text('Abrir configurações'),
            ),
          ],
        );
      },
    );
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
