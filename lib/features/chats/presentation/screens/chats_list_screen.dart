import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_mascot.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/domain/app_contact.dart';
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
  bool _showArchivedOnly = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  MessageStatus _parseThreadStatus(
    ChatThread thread, {
    required bool hideReadReceipts,
  }) {
    if (thread.hasPendingWrites) return MessageStatus.sending;
    switch (thread.lastMessageStatus) {
      case 'read':
        return hideReadReceipts
            ? MessageStatus.delivered
            : MessageStatus.read;
      case 'delivered':
        return MessageStatus.delivered;
      default:
        return MessageStatus.sent;
    }
  }

  void _showChatActionsSheet(
    ChatThread chat,
    String displayName,
  ) {
    final prefs = ref.read(chatPreferencesProvider);
    final isPinned = prefs.isPinned(chat.chatId);
    final isMuted = prefs.isMuted(chat.chatId);
    final isArchived = prefs.isArchived(chat.chatId);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(
                  isPinned ? 'Desafixar do topo' : 'Fixar no topo',
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ref
                      .read(chatPreferencesProvider.notifier)
                      .setChatPinned(chat.chatId, !isPinned);
                },
              ),
              ListTile(
                leading: Icon(
                  isMuted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                ),
                title: Text(
                  isMuted ? 'Reativar notificações' : 'Silenciar conversa',
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ref
                      .read(chatPreferencesProvider.notifier)
                      .setChatMuted(chat.chatId, !isMuted);
                },
              ),
              ListTile(
                leading: Icon(
                  isArchived
                      ? Icons.unarchive_rounded
                      : Icons.archive_rounded,
                ),
                title: Text(
                  isArchived ? 'Desarquivar conversa' : 'Arquivar conversa',
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ref
                      .read(chatPreferencesProvider.notifier)
                      .setChatArchived(chat.chatId, !isArchived);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: const Text('Ver perfil'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/chats/${chat.chatId}/profile');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  IconData? _mediaPreviewIcon(ChatThread thread) {
    switch (thread.lastMessageType) {
      case MessageTypes.image:
        return Icons.photo_camera_rounded;
      case MessageTypes.video:
        return Icons.videocam_rounded;
      case MessageTypes.file:
        return Icons.insert_drive_file_rounded;
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
        if (trimmed == 'Vídeo' || trimmed.startsWith('Vídeo')) {
          return Icons.videocam_rounded;
        }
        if (trimmed == 'Arquivo' || trimmed.startsWith('Arquivo:')) {
          return Icons.insert_drive_file_rounded;
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
                                  const ZapiMascot(
                                    mood: ZapiMascotMood.waiting,
                                    size: 92,
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

  Widget _buildChatTile({
    required BuildContext context,
    required ChatThread chat,
    required String myUid,
    required Map<String, AppContact> contactsByUid,
    required ChatPreferencesState prefs,
    required bool hideReadReceipts,
    required bool isDark,
    required Color secondaryText,
    required Color accentColor,
  }) {
    final otherUid = chat.otherParticipantUid(myUid);
    final savedContact = contactsByUid[otherUid];
    final threadProfile = chat.profileFor(otherUid);

    final displayName = savedContact?.effectiveName ??
        threadProfile?.displayName ??
        'Contato Zapi';
    final aboutText = (savedContact?.about.trim().isNotEmpty ?? false)
        ? savedContact!.about.trim()
        : (threadProfile?.about?.trim() ?? '');
    final photoBase64 = savedContact?.photoBase64 ?? threadProfile?.photoBase64;
    final photoUrl = savedContact?.photoUrl ?? threadProfile?.photoUrl;
    final unread = chat.unreadFor(myUid);
    final isTyping = chat.isTyping(otherUid);
    final sentByMe = chat.lastMessageSenderId == myUid;
    final isPinned = prefs.isPinned(chat.chatId);
    final isMuted = prefs.isMuted(chat.chatId);
    final draft = prefs.draftFor(chat.chatId);

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
              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
              color: unread > 0 ? accentColor : secondaryText,
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
                if (!isTyping && draft.isEmpty && sentByMe) ...[
                  MessageStatusIcon(
                    status: _parseThreadStatus(
                      chat,
                      hideReadReceipts: hideReadReceipts,
                    ),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                ],
                if (!isTyping && draft.isEmpty) ...[
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
                  child: isTyping
                      ? Text(
                          'digitando...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        )
                      : draft.isNotEmpty
                          ? Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Rascunho: ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                  TextSpan(
                                    text: draft.replaceAll('\n', ' '),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              _cleanLastMessageLabel(chat.lastMessage),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: secondaryText,
                              ),
                            ),
                ),
                if (isMuted) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.notifications_off_rounded,
                    size: 15,
                    color: secondaryText,
                  ),
                ],
                if (isPinned) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.push_pin_rounded,
                    size: 15,
                    color: secondaryText,
                  ),
                ],
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
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
      onLongPress: () => _showChatActionsSheet(chat, displayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid =
        ref.watch(authStateProvider.select((s) => s.value?.uid)) ?? '';
    final myUser = ref.watch(currentUserProfileProvider).value;
    final hideReadReceipts = myUser?.hideReadReceipts ?? false;
    final prefs = ref.watch(chatPreferencesProvider);
    final chatsAsync = ref.watch(userChatsProvider);
    final contactsByUid = ref.watch(contactsByUidProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accentColor = Theme.of(context).colorScheme.primary;

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
      final archivedCount =
          chats.where((c) => prefs.isArchived(c.chatId)).length;

      final scopedChats = normalizedQuery.isNotEmpty
          ? chats.where((chat) {
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
            }).toList()
          : chats
              .where(
                (chat) => _showArchivedOnly
                    ? prefs.isArchived(chat.chatId)
                    : !prefs.isArchived(chat.chatId),
              )
              .toList();

      scopedChats.sort((a, b) {
        final aPinned = prefs.isPinned(a.chatId);
        final bPinned = prefs.isPinned(b.chatId);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      final showArchivedRow =
          !_isSearching && !_showArchivedOnly && archivedCount > 0;

      if (scopedChats.isEmpty && !showArchivedRow) {
        bodyContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ZapiMascot(
                  mood: normalizedQuery.isNotEmpty
                      ? ZapiMascotMood.excited
                      : ZapiMascotMood.waiting,
                  size: 106,
                ),
                const SizedBox(height: 12),
                Text(
                  normalizedQuery.isNotEmpty
                      ? 'Nenhuma conversa encontrada'
                      : (_showArchivedOnly
                          ? 'Nenhuma conversa arquivada'
                          : 'Nenhuma conversa ainda'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  normalizedQuery.isNotEmpty
                      ? 'Tente buscar por outro nome ou @usuário.'
                      : (_showArchivedOnly
                          ? 'Segure uma conversa e toque em Arquivar para guardá-la aqui.'
                          : 'Toque em "Nova conversa" abaixo para escolher um contato e começar.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
              ],
            ),
          ),
        );
      } else {
        final itemCount = scopedChats.length + (showArchivedRow ? 1 : 0);
        bodyContent = ListView.separated(
          padding: const EdgeInsets.only(bottom: 88),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const Divider(indent: 78),
          itemBuilder: (context, index) {
            if (showArchivedRow && index == 0) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 4,
                ),
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.archive_rounded,
                    color: accentColor,
                    size: 22,
                  ),
                ),
                title: const Text(
                  'Conversas arquivadas',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
                trailing: Text(
                  '$archivedCount',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accentColor,
                  ),
                ),
                onTap: () => setState(() => _showArchivedOnly = true),
              );
            }

            final chat = scopedChats[showArchivedRow ? index - 1 : index];
            return _buildChatTile(
              context: context,
              chat: chat,
              myUid: myUid,
              contactsByUid: contactsByUid,
              prefs: prefs,
              hideReadReceipts: hideReadReceipts,
              isDark: isDark,
              secondaryText: secondaryText,
              accentColor: accentColor,
            );
          },
        );
      }
    }

    return PopScope(
      canPop: !_showArchivedOnly && !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          _toggleSearch();
        } else if (_showArchivedOnly) {
          setState(() => _showArchivedOnly = false);
        }
      },
      child: Scaffold(
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
              : Text(_showArchivedOnly ? 'Arquivadas' : 'Zapi'),
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _toggleSearch,
                )
              : (_showArchivedOnly
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () =>
                          setState(() => _showArchivedOnly = false),
                    )
                  : null),
          actions: [
            if (!_isSearching && !_showArchivedOnly) ...[
              IconButton(
                tooltip: 'Pesquisar conversas',
                icon: const Icon(Icons.search_rounded),
                onPressed: _toggleSearch,
              ),
              IconButton(
                tooltip: 'Configurações',
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => context.push('/settings'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.push('/profile'),
                  child: ZapiAvatar(
                    displayName: myUser?.displayName ?? 'Você',
                    photoBase64: myUser?.photoBase64,
                    photoUrl: myUser?.photoUrl,
                    radius: 17,
                  ),
                ),
              ),
            ],
          ],
        ),
        floatingActionButton: _showArchivedOnly
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openNewChatSheet(myUid),
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                tooltip: 'Nova conversa',
                icon: const Icon(Icons.chat_rounded),
                label: const Text(
                  'Nova conversa',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        body: bodyContent,
      ),
    );
  }
}
