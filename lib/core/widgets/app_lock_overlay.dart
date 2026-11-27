import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock_service.dart';
import '../services/chat_preferences_service.dart';
import '../theme/app_colors.dart';
import '../utils/pin_hasher.dart';
import 'zapi_mascot.dart';

class AppLockOverlay extends ConsumerStatefulWidget {
  const AppLockOverlay({super.key});

  @override
  ConsumerState<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends ConsumerState<AppLockOverlay> {
  String _pin = '';
  String? _errorText;
  bool _biometricAvailable = false;
  bool _biometricInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBiometric());
  }

  Future<void> _initBiometric() async {
    final prefs = ref.read(chatPreferencesProvider);
    final available = await AppLockBridge.isDeviceAuthAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available && prefs.appLockUseDeviceBiometric) {
      unawaited(_triggerDeviceAuth());
    }
  }

  Future<void> _triggerDeviceAuth() async {
    if (_biometricInFlight) return;
    setState(() => _biometricInFlight = true);
    try {
      final ok = await AppLockBridge.authenticateWithDevice();
      if (!mounted) return;
      if (ok) {
        unawaited(HapticFeedback.lightImpact());
        ref.read(appLockControllerProvider.notifier).unlock();
      }
    } finally {
      if (mounted) setState(() => _biometricInFlight = false);
    }
  }

  void _onDigitTap(String digit) {
    if (_pin.length >= 4) return;
    unawaited(HapticFeedback.selectionClick());
    final next = '$_pin$digit';
    setState(() {
      _pin = next;
      _errorText = null;
    });

    if (next.length == 4) {
      final hash = ref.read(chatPreferencesProvider).appLockPinHash;
      if (PinHasher.verifyPin(next, hash)) {
        unawaited(HapticFeedback.lightImpact());
        ref.read(appLockControllerProvider.notifier).unlock();
      } else {
        unawaited(HapticFeedback.heavyImpact());
        setState(() {
          _pin = '';
          _errorText = 'PIN incorreto. Tente novamente.';
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(chatPreferencesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final showDeviceButton =
        _biometricAvailable && prefs.appLockUseDeviceBiometric;

    return PopScope(
      canPop: false,
      child: Material(
        color: bgColor,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const ZapiMascot(
                      mood: ZapiMascotMood.resting,
                      size: 86,
                      animate: false,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Zapi bloqueado',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Digite seu PIN de 4 dígitos para continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryText, fontSize: 13.5),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final filled = index < _pin.length;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? AppColors.emerald
                                : Colors.transparent,
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
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 20,
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
                    const SizedBox(height: 18),
                    _PinPad(
                      isDark: isDark,
                      onDigit: _onDigitTap,
                      onBackspace: _onBackspace,
                      leftAction: showDeviceButton
                          ? _PadIconButton(
                              tooltip: 'Usar biometria',
                              icon: Icons.fingerprint_rounded,
                              color: AppColors.emerald,
                              onTap: _triggerDeviceAuth,
                            )
                          : const SizedBox(width: 68, height: 68),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.isDark,
    required this.onDigit,
    required this.onBackspace,
    required this.leftAction,
  });

  final bool isDark;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Widget leftAction;

  @override
  Widget build(BuildContext context) {
    Widget keyButton(String label) {
      return SizedBox(
        width: 68,
        height: 68,
        child: Material(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onDigit(label),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [keyButton('1'), keyButton('2'), keyButton('3')],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [keyButton('4'), keyButton('5'), keyButton('6')],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [keyButton('7'), keyButton('8'), keyButton('9')],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            leftAction,
            keyButton('0'),
            _PadIconButton(
              tooltip: 'Apagar',
              icon: Icons.backspace_rounded,
              onTap: onBackspace,
            ),
          ],
        ),
      ],
    );
  }
}

class _PadIconButton extends StatelessWidget {
  const _PadIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 26, color: color),
      ),
    );
  }
}
