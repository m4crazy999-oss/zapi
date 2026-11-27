import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/app_lock_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/chat_preferences_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/presence_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/app_lock_overlay.dart';
import 'core/widgets/update_dialog.dart';
import 'features/auth/domain/app_user.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/profile/presentation/providers/profile_providers.dart';

class ZapiApp extends ConsumerStatefulWidget {
  const ZapiApp({super.key});

  @override
  ConsumerState<ZapiApp> createState() => _ZapiAppState();
}

class _ZapiAppState extends ConsumerState<ZapiApp> with WidgetsBindingObserver {
  String? _activeSessionUid;
  AppReleaseUpdate? _mandatoryUpdate;
  bool _isCheckingUpdate = false;
  bool _initialLockEvaluated = false;

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
      _evaluateInitialLock(ref.read(chatPreferencesProvider));
      unawaited(_checkForUpdates());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _evaluateInitialLock(ChatPreferencesState prefs) {
    if (_initialLockEvaluated || !prefs.isLoaded) return;
    _initialLockEvaluated = true;
    final user = ref.read(authStateProvider).value;
    if (user != null && prefs.hasAppLockConfigured) {
      ref.read(appLockControllerProvider.notifier).lock();
    }
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
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      presence.setAppForeground(false);
      notifications.setAppForeground(false);
      final prefs = ref.read(chatPreferencesProvider);
      final user = ref.read(authStateProvider).value;
      if (state != AppLifecycleState.detached &&
          user != null &&
          prefs.hasAppLockConfigured &&
          !AppLockBridge.isPromptActive) {
        ref.read(appLockControllerProvider.notifier).lock();
      }
    } else if (state == AppLifecycleState.inactive) {
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
      ref.read(appLockControllerProvider.notifier).unlock();
      ref.read(presenceServiceProvider).unbind();
      unawaited(ref.read(notificationServiceProvider).clearSession());
    }
  }

  Future<void> _initializeUserSession(String uid) async {
    await ref.read(authRepositoryProvider).migrateAccountPrivacyIfNeeded();
    if (!mounted || _activeSessionUid != uid) return;

    final profile = ref.read(currentUserProfileProvider).value;
    await ref
        .read(presenceServiceProvider)
        .setHideLastSeen(profile?.hideLastSeen ?? false);
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
    final isAppLocked = ref.watch(appLockControllerProvider);
    final prefs = ref.watch(chatPreferencesProvider);
    final hasSession = ref.watch(authStateProvider).value != null;

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

    ref.listen<ChatPreferencesState>(
      chatPreferencesProvider,
      (_, next) => _evaluateInitialLock(next),
    );

    ref.listen<AsyncValue<AppUser?>>(
      currentUserProfileProvider,
      (_, next) {
        final user = next.value;
        if (user != null) {
          unawaited(
            ref
                .read(presenceServiceProvider)
                .setHideLastSeen(user.hideLastSeen),
          );
        }
      },
    );

    final showLock =
        isAppLocked && hasSession && prefs.hasAppLockConfigured;

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
            if (showLock)
              const Positioned.fill(
                child: AppLockOverlay(),
              ),
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
