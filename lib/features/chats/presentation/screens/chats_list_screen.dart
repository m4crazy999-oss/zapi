import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_thread.dart';
import '../providers/chats_providers.dart';
import '../widgets/message_bubble.dart';

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});

  @override
  ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  MessageStatus _parseThreadStatus(ChatThread thread) {
    if (thread.hasPendingWrites) return MessageStatus.sending;
    switch (thread.lastMessageStatus) {
      case 'read':
        return MessageStatus.read;
      case 'delivered':
        return MessageStatus.delivered;
      default:
        return MessageStatus.sent;
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(firebaseAuthProvider).currentUser?.uid ?? '';
    final profile = ref.watch(currentUserProfileProvider).value;
    final chatsAsync = ref.watch(userChatsProvider);
    final contactsByUid = ref.watch(contactsByUidProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    ref.listen<AsyncValue<List<ChatThread>>>(userChatsProvider, (_, next) {
      final list = next.value;
      if (list != null && myUid.isNotEmpty) {
        ref.read(chatsRepositoryProvider).markIncomingChatsDelivered(
              currentUid: myUid,
              chats: list,
            );
      }
    });

    final normalizedQuery = _searchQuery.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Pesquisar conversas...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              )
            : const Text('Zapi'),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _toggleSearch,
              )
            : null,
        actions: [
          if (!_isSearching)
            IconButton(
              tooltip: 'Adicionar contato por ID',
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: () => context.push('/contacts/add'),
            ),
          if (!_isSearching)
            IconButton(
              tooltip: 'Pesquisar conversas',
              icon: const Icon(Icons.search_rounded),
              onPressed: _toggleSearch,
            ),
          if (profile != null && !_isSearching)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ZapiAvatar(
                displayName: profile.displayName,
                photoBase64: profile.photoBase64,
                photoUrl: profile.photoUrl,
                radius: 18,
                onTap: () => context.push('/profile'),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/contacts/add'),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        tooltip: 'Adicionar contato por ID',
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Adicionar ID',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: chatsAsync.when(
        loading: () => const ZapiListSkeleton(),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Não foi possível carregar suas conversas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText),
            ),
          ),
        ),
        data: (chats) {
          final visibleChats = normalizedQuery.isEmpty
              ? chats
              : chats.where((chat) {
                  final otherUid = chat.otherParticipantUid(myUid);
                  final savedContact = contactsByUid[otherUid];
                  final threadProfile = chat.profileFor(otherUid);
                  final displayName = savedContact?.effectiveName ??
                      threadProfile?.displayName ??
                      '';
                  final username = savedContact?.username ??
                      threadProfile?.username ??
                      '';
                  return displayName.toLowerCase().contains(normalizedQuery) ||
                      username.toLowerCase().contains(normalizedQuery) ||
                      chat.lastMessage.toLowerCase().contains(normalizedQuery);
                }).toList();

          if (visibleChats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        normalizedQuery.isNotEmpty
                            ? Icons.search_off_rounded
                            : Icons.forum_outlined,
                        size: 38,
                        color: AppColors.emerald,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      normalizedQuery.isNotEmpty
                          ? 'Nenhuma conversa encontrada'
                          : 'Nenhuma conversa ainda',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      normalizedQuery.isNotEmpty
                          ? 'Tente buscar por outro nome ou @usuário.'
                          : 'Adicione alguém pelo ID exclusivo para que ele apareça nos seus Contatos e comece a conversar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryText),
                    ),
                    if (normalizedQuery.isEmpty) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => context.push('/contacts/add'),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Adicionar por ID'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => context.go('/contacts'),
                        icon: const Icon(Icons.people_outline_rounded),
                        label: const Text('Ver Contatos'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: visibleChats.length,
            separatorBuilder: (_, __) => const Divider(indent: 78),
            itemBuilder: (context, index) {
              final chat = visibleChats[index];
              final otherUid = chat.otherParticipantUid(myUid);
              final savedContact = contactsByUid[otherUid];
              final threadProfile = chat.profileFor(otherUid);

              final displayName = savedContact?.effectiveName ??
                  threadProfile?.displayName ??
                  'Contato Zapi';
              final photoBase64 =
                  savedContact?.photoBase64 ?? threadProfile?.photoBase64;
              final photoUrl =
                  savedContact?.photoUrl ?? threadProfile?.photoUrl;
              final unread = chat.unreadFor(myUid);
              final isTyping = chat.isTyping(otherUid);
              final sentByMe = chat.lastMessageSenderId == myUid;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: ZapiAvatar(
                  displayName: displayName,
                  photoBase64: photoBase64,
                  photoUrl: photoUrl,
                  radius: 26,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormatter.formatChatListTimestamp(chat.lastMessageAt),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            unread > 0 ? FontWeight.w700 : FontWeight.w500,
                        color: unread > 0
                            ? (isDark
                                ? AppColors.emeraldBright
                                : AppColors.emeraldDark)
                            : secondaryText,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      if (!isTyping && sentByMe) ...[
                        MessageStatusIcon(
                          status: _parseThreadStatus(chat),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          isTyping ? 'digitando...' : chat.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isTyping
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isTyping
                                ? (isDark
                                    ? AppColors.emeraldBright
                                    : AppColors.emeraldDark)
                                : secondaryText,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emerald,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                onTap: () => context.push('/chats/${chat.chatId}'),
              );
            },
          );
        },
      ),
    );
  }
}
