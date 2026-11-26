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
  bool _updateDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleAuthChange(ref.read(authStateProvider));
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
      if (ref.read(firebaseAuthProvider).currentUser != null) {
        unawaited(_checkForUpdatesIfNeeded());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      presence.setAppForeground(false);
      notifications.setAppForeground(false);
    }
  }

  void _handleAuthChange(AsyncValue<User?> next) {
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
    unawaited(ref.read(notificationServiceProvider).initializeForUser(uid));
    unawaited(_checkForUpdatesIfNeeded());
  }

  Future<void> _checkForUpdatesIfNeeded() async {
    if (_updateDialogVisible) return;
    final updateService = ref.read(appUpdateServiceProvider);
    final update = await updateService.checkForUpdate(force: false);
    if (!mounted || update == null || _updateDialogVisible) return;

    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    _updateDialogVisible = true;
    try {
      await UpdateDialog.show(
        navContext,
        update: update,
        updateService: updateService,
      );
    } finally {
      _updateDialogVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, next) => _handleAuthChange(next),
    );

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
