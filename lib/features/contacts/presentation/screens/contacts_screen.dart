import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_mascot.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/app_contact.dart';
import '../providers/contacts_providers.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(AppContact contact) {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (myUid == null) return;
    final chatId = ChatIdHelper.buildDirectChatId(myUid, contact.contactUid);
    context.push('/chats/$chatId');
  }

  void _openPeerProfile(AppContact contact) {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (myUid == null) return;
    final chatId = ChatIdHelper.buildDirectChatId(myUid, contact.contactUid);
    context.push('/chats/$chatId/profile');
  }

  Future<void> _toggleFavorite(AppContact contact) async {
    try {
      await ref.read(contactsControllerProvider.notifier).setFavorite(
            contactUid: contact.contactUid,
            isFavorite: !contact.isFavorite,
          );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(filteredContactsProvider);
    final query = ref.watch(contactsSearchQueryProvider);
    final myUser = ref.watch(currentUserProfileProvider).value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatos'),
        actions: [
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/contacts/add'),
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Adicionar contato por ID',
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Adicionar contato',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => ref
                  .read(contactsSearchQueryProvider.notifier)
                  .setQuery(value),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, @usuário ou recado...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(contactsSearchQueryProvider.notifier)
                              .setQuery('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: contactsAsync.when(
              loading: () => const ZapiListSkeleton(showTimestamp: false),
              error: (_, __) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: ZapiMascotWithBubble(
                    mood: ZapiMascotMood.waiting,
                    mascotSize: 92,
                    message:
                        'Ops! Não consegui carregar seus contatos agora.',
                  ),
                ),
              ),
              data: (contacts) {
                if (contacts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: ZapiMascotWithBubble(
                        mood: query.isNotEmpty
                            ? ZapiMascotMood.excited
                            : ZapiMascotMood.waiting,
                        mascotSize: 100,
                        message: query.isNotEmpty
                            ? 'Nenhum contato combina com "$query".'
                            : 'Sua lista está vazia! Toque em "Adicionar contato" para encontrar alguém.',
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: ZapiAvatar(
                        displayName: contact.effectiveName,
                        photoBase64: contact.photoBase64,
                        photoUrl: contact.photoUrl,
                        radius: 25,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.effectiveName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '@${contact.username}',
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        contact.about.trim().isNotEmpty
                            ? contact.about
                            : 'Sem recado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondaryText, fontSize: 13.5),
                      ),
                      trailing: IconButton(
                        tooltip: contact.isFavorite
                            ? 'Remover dos favoritos'
                            : 'Marcar como favorito',
                        onPressed: () => _toggleFavorite(contact),
                        icon: Icon(
                          contact.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: contact.isFavorite
                              ? const Color(0xFFF59E0B)
                              : secondaryText,
                        ),
                      ),
                      onTap: () => _openChat(contact),
                      onLongPress: () => _openPeerProfile(contact),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
