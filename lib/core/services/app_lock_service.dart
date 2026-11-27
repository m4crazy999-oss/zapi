import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLockBridge {
  AppLockBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.zapi.chat/media_bridge');

  static bool isPromptActive = false;

  static Future<bool> isDeviceAuthAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('isDeviceAuthAvailable');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithDevice({
    String title = 'Desbloquear Zapi',
    String subtitle = 'Confirme sua biometria ou senha do celular',
  }) async {
    if (!Platform.isAndroid) return false;
    isPromptActive = true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'authenticateWithDevice',
        {
          'title': title,
          'subtitle': subtitle,
        },
      );
      return result == true;
    } catch (_) {
      return false;
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        isPromptActive = false;
      });
    }
  }
}

class AppLockController extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() {
    if (!state) state = true;
  }

  void unlock() {
    if (state) state = false;
  }
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, bool>(AppLockController.new);
