import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/chat_message.dart';
import '../../domain/chat_thread.dart';
import '../providers/chats_providers.dart';
import '../widgets/message_bubble.dart';

class ChatsListScreen extends ConsumerWidget {
  const ChatsListScreen({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zapi'),
        actions: [
          if (profile != null)
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/contacts'),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        tooltip: 'Nova conversa',
        child: const Icon(Icons.chat_rounded),
      ),
      body: chatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
          if (chats.isEmpty) {
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
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 38,
                        color: AppColors.emerald,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Nenhuma conversa ainda',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Adicione um contato pelo @usuário ou e-mail e comece a conversar em tempo real.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryText),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.go('/contacts'),
                      icon: const Icon(Icons.people_outline_rounded),
                      label: const Text('Ir para Contatos'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(indent: 78),
            itemBuilder: (context, index) {
              final chat = chats[index];
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
