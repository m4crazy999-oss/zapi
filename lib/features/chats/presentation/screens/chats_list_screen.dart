import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
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
  final Map<String, String> _deliveredMessageTokens = {};
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

  IconData? _mediaPreviewIcon(ChatThread thread) {
    switch (thread.lastMessageType) {
      case MessageTypes.image:
        return Icons.photo_camera_rounded;
      case MessageTypes.audio:
        return Icons.mic_rounded;
      case MessageTypes.sticker:
        return Icons.sticky_note_2_rounded;
      case MessageTypes.text:
        return null;
      default:
        final trimmed = thread.lastMessage.trim();
        if (trimmed.startsWith('\u{1F4F7}') ||
            trimmed == 'Foto' ||
            trimmed.startsWith('Foto:')) {
          return Icons.photo_camera_rounded;
        }
        if (trimmed.startsWith('\u{1F3A4}') || trimmed.startsWith('Áudio ')) {
          return Icons.mic_rounded;
        }
        if (trimmed == 'Figurinha') {
          return Icons.sticky_note_2_rounded;
        }
        return null;
    }
  }

  String _cleanLastMessageLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('\u{1F4F7} ')) return trimmed.substring(2).trimLeft();
    if (trimmed.startsWith('\u{1F3A4} ')) return trimmed.substring(2).trimLeft();
    return raw;
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

  void _scheduleIncomingDelivery(String myUid, List<ChatThread> chats) {
    if (myUid.isEmpty) return;
    final toMark = <ChatThread>[];
    for (final chat in chats) {
      final msgId = chat.lastMessageId;
      if (msgId == null || msgId.isEmpty) continue;
      if (!chat.hasPendingWrites &&
          chat.lastMessageSenderId != null &&
          chat.lastMessageSenderId != myUid &&
          chat.lastMessageStatus == 'sent' &&
          _deliveredMessageTokens[chat.chatId] != msgId) {
        _deliveredMessageTokens[chat.chatId] = msgId;
        toMark.add(chat);
      }
    }
    if (toMark.isNotEmpty) {
      ref.read(chatsRepositoryProvider).markIncomingChatsDelivered(
            currentUid: myUid,
            chats: toMark,
          );
    }
  }

  void _openNewChatSheet(String myUid) {
    if (myUid.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (context, ref, _) {
            final contactsAsync = ref.watch(contactsListProvider);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final secondaryText = isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary;

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.68,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        'Nova conversa',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: contactsAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (_, __) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Não foi possível carregar seus contatos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: secondaryText),
                          ),
                        ),
                        data: (contacts) {
                          if (contacts.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.people_rounded,
                                    size: 42,
                                    color: secondaryText,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Você ainda não adicionou contatos.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Adicione alguém na aba Contatos para iniciar uma conversa.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.pop(sheetCtx);
                                      context.go('/contacts');
                                    },
                                    icon: const Icon(Icons.people_rounded),
                                    label: const Text('Ir para Contatos'),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            itemCount: contacts.length,
                            separatorBuilder: (_, __) =>
                                const Divider(indent: 74, height: 1),
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              return ListTile(
                                leading: ZapiAvatar(
                                  displayName: contact.effectiveName,
                                  photoBase64: contact.photoBase64,
                                  photoUrl: contact.photoUrl,
                                  radius: 22,
                                ),
                                title: Text(
                                  contact.effectiveName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  contact.about.trim().isNotEmpty
                                      ? contact.about
                                      : '@${contact.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  final chatId = ChatIdHelper.buildDirectChatId(
                                    myUid,
                                    contact.contactUid,
                                  );
                                  context.push('/chats/$chatId');
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid =
        ref.watch(authStateProvider.select((s) => s.value?.uid)) ?? '';
    final chatsAsync = ref.watch(userChatsProvider);
    final contactsByUid = ref.watch(contactsByUidProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    ref.listen<AsyncValue<List<ChatThread>>>(userChatsProvider, (_, next) {
      final list = next.value;
      if (list != null && myUid.isNotEmpty) {
        _scheduleIncomingDelivery(myUid, list);
      }
    });

    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final chats = chatsAsync.value;

    Widget bodyContent;
    if (chats == null) {
      if (chatsAsync.hasError) {
        bodyContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Não foi possível carregar suas conversas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(userChatsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        );
      } else {
        bodyContent = const ZapiListSkeleton();
      }
    } else {
      final visibleChats = normalizedQuery.isEmpty
          ? chats
          : chats.where((chat) {
              final otherUid = chat.otherParticipantUid(myUid);
              final savedContact = contactsByUid[otherUid];
              final threadProfile = chat.profileFor(otherUid);
              final displayName = savedContact?.effectiveName ??
                  threadProfile?.displayName ??
                  '';
              final username =
                  savedContact?.username ?? threadProfile?.username ?? '';
              final about =
                  savedContact?.about ?? threadProfile?.about ?? '';
              return displayName.toLowerCase().contains(normalizedQuery) ||
                  username.toLowerCase().contains(normalizedQuery) ||
                  about.toLowerCase().contains(normalizedQuery) ||
                  chat.lastMessage.toLowerCase().contains(normalizedQuery);
            }).toList();

      if (visibleChats.isEmpty) {
        bodyContent = Center(
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
                        : Icons.forum_rounded,
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
                      : 'Toque em "Nova conversa" abaixo para escolher um contato e começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
              ],
            ),
          ),
        );
      } else {
        bodyContent = ListView.separated(
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
            final aboutText = (savedContact?.about.trim().isNotEmpty ?? false)
                ? savedContact!.about.trim()
                : (threadProfile?.about?.trim() ?? '');
            final photoBase64 =
                savedContact?.photoBase64 ?? threadProfile?.photoBase64;
            final photoUrl = savedContact?.photoUrl ?? threadProfile?.photoUrl;
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
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (aboutText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          aboutText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryText.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        if (!isTyping && sentByMe) ...[
                          MessageStatusIcon(
                            status: _parseThreadStatus(chat),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (!isTyping) ...[
                          Builder(
                            builder: (context) {
                              final icon = _mediaPreviewIcon(chat);
                              if (icon == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  icon,
                                  size: 15,
                                  color: secondaryText,
                                ),
                              );
                            },
                          ),
                        ],
                        Expanded(
                          child: Text(
                            isTyping
                                ? 'digitando...'
                                : _cleanLastMessageLabel(chat.lastMessage),
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
                  ],
                ),
              ),
              onTap: () => context.push('/chats/${chat.chatId}'),
            );
          },
        );
      }
    }

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
              tooltip: 'Pesquisar conversas',
              icon: const Icon(Icons.search_rounded),
              onPressed: _toggleSearch,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewChatSheet(myUid),
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        tooltip: 'Nova conversa',
        icon: const Icon(Icons.chat_rounded),
        label: const Text(
          'Nova conversa',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: bodyContent,
    );
  }
}
