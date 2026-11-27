import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_lock_service.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/pin_hasher.dart';

enum _LockSheetMode {
  manage,
  verifyToChange,
  verifyToDisable,
  createPin,
  confirmPin,
}

class AppLockSheet extends ConsumerStatefulWidget {
  const AppLockSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const AppLockSheet(),
    );
  }

  @override
  ConsumerState<AppLockSheet> createState() => _AppLockSheetState();
}

class _AppLockSheetState extends ConsumerState<AppLockSheet> {
  late _LockSheetMode _mode;
  String _pin = '';
  String _firstPin = '';
  String? _errorText;
  bool _deviceAuthAvailable = false;
  bool _enableDeviceAuthOnCreate = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(chatPreferencesProvider);
    _mode = prefs.hasAppLockConfigured
        ? _LockSheetMode.manage
        : _LockSheetMode.createPin;
    _enableDeviceAuthOnCreate = prefs.appLockUseDeviceBiometric;
    _checkDeviceAuth();
  }

  Future<void> _checkDeviceAuth() async {
    final available = await AppLockBridge.isDeviceAuthAvailable();
    if (!mounted) return;
    setState(() {
      _deviceAuthAvailable = available;
      if (_mode == _LockSheetMode.createPin && available) {
        _enableDeviceAuthOnCreate = true;
      }
    });
  }

  void _onDigitTap(String digit) {
    if (_busy || _pin.length >= 4) return;
    unawaited(HapticFeedback.selectionClick());
    final next = '$_pin$digit';
    setState(() {
      _pin = next;
      _errorText = null;
    });

    if (next.length == 4) {
      unawaited(_handleCompletedPin(next));
    }
  }

  Future<void> _handleCompletedPin(String entered) async {
    final prefs = ref.read(chatPreferencesProvider);
    final prefsNotifier = ref.read(chatPreferencesProvider.notifier);

    switch (_mode) {
      case _LockSheetMode.manage:
        return;

      case _LockSheetMode.verifyToChange:
        if (PinHasher.verifyPin(entered, prefs.appLockPinHash)) {
          unawaited(HapticFeedback.lightImpact());
          setState(() {
            _mode = _LockSheetMode.createPin;
            _pin = '';
            _firstPin = '';
            _errorText = null;
          });
        } else {
          unawaited(HapticFeedback.heavyImpact());
          setState(() {
            _pin = '';
            _errorText = 'PIN atual incorreto.';
          });
        }
        return;

      case _LockSheetMode.verifyToDisable:
        if (PinHasher.verifyPin(entered, prefs.appLockPinHash)) {
          setState(() => _busy = true);
          await prefsNotifier.disableAppLock();
          if (!mounted) return;
          ref.read(appLockControllerProvider.notifier).unlock();
          Navigator.pop(context);
        } else {
          unawaited(HapticFeedback.heavyImpact());
          setState(() {
            _pin = '';
            _errorText = 'PIN atual incorreto.';
          });
        }
        return;

      case _LockSheetMode.createPin:
        unawaited(HapticFeedback.selectionClick());
        setState(() {
          _firstPin = entered;
          _pin = '';
          _errorText = null;
          _mode = _LockSheetMode.confirmPin;
        });
        return;

      case _LockSheetMode.confirmPin:
        if (entered != _firstPin) {
          unawaited(HapticFeedback.heavyImpact());
          setState(() {
            _pin = '';
            _firstPin = '';
            _mode = _LockSheetMode.createPin;
            _errorText = 'Os PINs não coincidem. Digite novamente.';
          });
          return;
        }
        setState(() => _busy = true);
        final hash = PinHasher.createSaltedHash(entered);
        final useBio = _deviceAuthAvailable && _enableDeviceAuthOnCreate;
        await prefsNotifier.enableAppLock(
          pinHash: hash,
          useDeviceBiometric: useBio,
        );
        if (!mounted) return;
        ref.read(appLockControllerProvider.notifier).unlock();
        Navigator.pop(context);
        return;
    }
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  String get _title {
    switch (_mode) {
      case _LockSheetMode.manage:
        return 'Bloqueio do app';
      case _LockSheetMode.verifyToChange:
        return 'Confirme o PIN atual';
      case _LockSheetMode.verifyToDisable:
        return 'Desativar bloqueio';
      case _LockSheetMode.createPin:
        return 'Criar PIN de 4 dígitos';
      case _LockSheetMode.confirmPin:
        return 'Confirmar novo PIN';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _LockSheetMode.manage:
        return 'O Zapi pede autenticação ao abrir ou voltar para o app.';
      case _LockSheetMode.verifyToChange:
        return 'Digite seu PIN atual para escolher um novo.';
      case _LockSheetMode.verifyToDisable:
        return 'Digite seu PIN atual para remover o bloqueio.';
      case _LockSheetMode.createPin:
        return 'Escolha um PIN de 4 dígitos para proteger suas conversas.';
      case _LockSheetMode.confirmPin:
        return 'Digite novamente os 4 dígitos para confirmar.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(chatPreferencesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark ? AppColors.emeraldBright : AppColors.emeraldDark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: _mode == _LockSheetMode.manage
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle,
                    style: TextStyle(color: secondaryText, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_deviceAuthAvailable) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.fingerprint_rounded, color: accent),
                      title: const Text('Desbloquear com biometria'),
                      subtitle: const Text(
                        'Usa digital, rosto ou bloqueio do celular além do PIN',
                      ),
                      value: prefs.appLockUseDeviceBiometric,
                      onChanged: (value) => ref
                          .read(chatPreferencesProvider.notifier)
                          .setAppLockDeviceBiometric(value),
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.pin_rounded, color: accent),
                    title: const Text('Alterar PIN'),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: secondaryText,
                    ),
                    onTap: () {
                      setState(() {
                        _mode = _LockSheetMode.verifyToChange;
                        _pin = '';
                        _errorText = null;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.lock_open_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Desativar bloqueio',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _mode = _LockSheetMode.verifyToDisable;
                        _pin = '';
                        _errorText = null;
                      });
                    },
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondaryText, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final filled = index < _pin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              filled ? AppColors.emerald : Colors.transparent,
                          border: Border.all(
                            color: _errorText != null
                                ? Theme.of(context).colorScheme.error
                                : (filled
                                    ? AppColors.emerald
                                    : secondaryText.withValues(alpha: 0.45)),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 18,
                    child: _errorText != null
                        ? Text(
                            _errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_deviceAuthAvailable &&
                      (_mode == _LockSheetMode.createPin ||
                          _mode == _LockSheetMode.confirmPin)) ...[
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(Icons.fingerprint_rounded, color: accent),
                      title: const Text('Permitir biometria do celular'),
                      value: _enableDeviceAuthOnCreate,
                      onChanged: (value) =>
                          setState(() => _enableDeviceAuthOnCreate = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SheetPinPad(
                    isDark: isDark,
                    onDigit: _onDigitTap,
                    onBackspace: _onBackspace,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SheetPinPad extends StatelessWidget {
  const _SheetPinPad({
    required this.isDark,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool isDark;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget keyButton(String label) {
      return SizedBox(
        width: 64,
        height: 54,
        child: Material(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onDigit(label),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [keyButton('1'), keyButton('2'), keyButton('3')],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [keyButton('4'), keyButton('5'), keyButton('6')],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [keyButton('7'), keyButton('8'), keyButton('9')],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 64, height: 54),
              keyButton('0'),
              SizedBox(
                width: 64,
                height: 54,
                child: IconButton(
                  tooltip: 'Apagar',
                  onPressed: onBackspace,
                  icon: const Icon(Icons.backspace_rounded, size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
