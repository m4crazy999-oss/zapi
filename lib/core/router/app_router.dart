import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/chats/domain/chat_message.dart';
import '../../features/chats/presentation/screens/chat_screen.dart';
import '../../features/chats/presentation/screens/chats_list_screen.dart';
import '../../features/contacts/presentation/screens/add_contact_screen.dart';
import '../../features/contacts/presentation/screens/contacts_screen.dart';
import '../../features/home/presentation/screens/home_shell_screen.dart';
import '../../features/profile/presentation/screens/peer_profile_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/status/presentation/screens/status_screen.dart';
import '../../features/stickers/presentation/screens/create_sticker_screen.dart';
import '../services/notification_service.dart';
import '../widgets/zapi_logo.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    _authSub = ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
    _holdSub = ref.listen<bool>(
      authRedirectHoldProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<User?>> _authSub;
  late final ProviderSubscription<bool> _holdSub;

  @override
  void dispose() {
    _authSub.close();
    _holdSub.close();
    super.dispose();
  }
}

CustomTransitionPage<void> _buildSmoothPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 190),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final holdRedirect = ref.read(authRedirectHoldProvider);
      final location = state.matchedLocation;

      if (holdRedirect) {
        return null;
      }

      if (authAsync.isLoading) {
        return location == '/splash' ? null : '/splash';
      }

      final user = authAsync.value;
      final isLoggedIn = user != null;
      final isAuthOnlyRoute = location == '/login' || location == '/register';
      final isPublicAuthRoute = isAuthOnlyRoute || location == '/forgot-password';

      if (!isLoggedIn) {
        return isPublicAuthRoute ? null : '/login';
      }

      if (location == '/splash' || isAuthOnlyRoute) {
        return '/chats';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SessionLoadingScreen(),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildSmoothPage(
          state,
          const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _buildSmoothPage(
          state,
          const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _buildSmoothPage(
          state,
          const ForgotPasswordScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShellScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/status',
                builder: (context, state) => const StatusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (context, state) => const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/chats/:chatId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          final initialReply =
              state.extra is ReplyQuote ? state.extra as ReplyQuote : null;
          return _buildSmoothPage(
            state,
            ChatScreen(chatId: chatId, initialReply: initialReply),
          );
        },
      ),
      GoRoute(
        path: '/chats/:chatId/profile',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          return _buildSmoothPage(state, PeerProfileScreen(chatId: chatId));
        },
      ),
      GoRoute(
        path: '/contacts/add',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildSmoothPage(state, const AddContactScreen()),
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildSmoothPage(state, const ProfileScreen()),
      ),
      GoRoute(
        path: '/stickers/create',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _buildSmoothPage(state, const CreateStickerScreen()),
      ),
    ],
  );

  ref.read(notificationServiceProvider).attachNavigationHandler((chatId) {
    if (chatId.isEmpty) return;
    final targetPath = '/chats/$chatId';
    if (router.routeInformationProvider.value.uri.path == targetPath) {
      return;
    }
    router.go('/chats');
    router.push(targetPath);
  });

  return router;
});

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ZapiLogo(size: 84, showLabel: true),
            SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
