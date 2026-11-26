import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/services/presence_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

class ZapiApp extends ConsumerStatefulWidget {
  const ZapiApp({super.key});

  @override
  ConsumerState<ZapiApp> createState() => _ZapiAppState();
}

class _ZapiAppState extends ConsumerState<ZapiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      presence.setAppForeground(false);
      notifications.setAppForeground(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, next) {
        final user = next.value;
        if (user != null) {
          ref.read(presenceServiceProvider).bindUser(user.uid);
          ref.read(notificationServiceProvider).initializeForUser(user.uid);
        } else if (!next.isLoading) {
          ref.read(presenceServiceProvider).unbind();
          unawaited(ref.read(notificationServiceProvider).clearSession());
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
    );
  }
}
