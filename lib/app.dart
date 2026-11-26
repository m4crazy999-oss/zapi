import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/app_update_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/presence_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/update_dialog.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

class ZapiApp extends ConsumerStatefulWidget {
  const ZapiApp({super.key});

  @override
  ConsumerState<ZapiApp> createState() => _ZapiAppState();
}

class _ZapiAppState extends ConsumerState<ZapiApp> with WidgetsBindingObserver {
  String? _activeSessionUid;
  AppReleaseUpdate? _mandatoryUpdate;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleAuthChange(
        ref.read(authStateProvider),
        ref.read(authRedirectHoldProvider),
      );
      unawaited(_checkForUpdates());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final presence = ref.read(presenceServiceProvider);
    final notifications = ref.read(notificationServiceProvider);
    if (state == AppLifecycleState.resumed) {
      presence.setAppForeground(true);
      notifications.setAppForeground(true);
      unawaited(_checkForUpdates());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      presence.setAppForeground(false);
      notifications.setAppForeground(false);
    }
  }

  void _handleAuthChange(AsyncValue<User?> next, bool holdRedirect) {
    if (holdRedirect) return;

    final user = next.value;
    if (user != null) {
      if (_activeSessionUid == user.uid) return;
      _activeSessionUid = user.uid;
      unawaited(_initializeUserSession(user.uid));
    } else if (!next.isLoading) {
      _activeSessionUid = null;
      ref.read(presenceServiceProvider).unbind();
      unawaited(ref.read(notificationServiceProvider).clearSession());
    }
  }

  Future<void> _initializeUserSession(String uid) async {
    await ref.read(authRepositoryProvider).migrateAccountPrivacyIfNeeded();
    if (!mounted || _activeSessionUid != uid) return;

    ref.read(presenceServiceProvider).bindUser(uid);
    await ref.read(notificationServiceProvider).initializeForUser(uid);
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdate) return;
    _isCheckingUpdate = true;
    try {
      final updateService = ref.read(appUpdateServiceProvider);
      final update = await updateService.checkForUpdate();
      if (!mounted) return;
      if (update != null &&
          (_mandatoryUpdate == null ||
              update.remoteBuildNumber > _mandatoryUpdate!.remoteBuildNumber)) {
        setState(() {
          _mandatoryUpdate = update;
        });
      }
    } finally {
      _isCheckingUpdate = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, next) => _handleAuthChange(
        next,
        ref.read(authRedirectHoldProvider),
      ),
    );

    ref.listen<bool>(
      authRedirectHoldProvider,
      (_, holdRedirect) {
        if (!holdRedirect) {
          _handleAuthChange(ref.read(authStateProvider), false);
        }
      },
    );

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final pendingUpdate = _mandatoryUpdate;
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (pendingUpdate != null)
              Positioned.fill(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => UpdateRequiredScreen(
                      update: pendingUpdate,
                      updateService: ref.read(appUpdateServiceProvider),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
