import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chats/presentation/providers/chats_providers.dart';

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(authRepositoryProvider).updateLastSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authRepositoryProvider).updateLastSeen();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid =
        ref.watch(authStateProvider.select((s) => s.value?.uid)) ?? '';
    final chats = ref.watch(userChatsProvider).value ?? const [];
    final totalUnread = myUid.isEmpty
        ? 0
        : chats.fold<int>(0, (sum, c) => sum + c.unreadFor(myUid));

    return Scaffold(
      body: TweenAnimationBuilder<double>(
        key: ValueKey(widget.navigationShell.currentIndex),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 165),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 6),
              child: child,
            ),
          );
        },
        child: widget.navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat_bubble_rounded),
            ),
            label: 'Conversas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.donut_large_rounded),
            selectedIcon: Icon(Icons.donut_large_rounded),
            label: 'Status',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Contatos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Configurações',
          ),
        ],
      ),
    );
  }
}
