import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(filteredContactsProvider);
    final query = ref.watch(contactsSearchQueryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatos'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/contacts/add'),
        backgroundColor: AppColors.emerald,
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
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Não foi possível carregar seus contatos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondaryText),
                  ),
                ),
              ),
              data: (contacts) {
                if (contacts.isEmpty) {
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
                              Icons.people_rounded,
                              size: 38,
                              color: AppColors.emerald,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            query.isNotEmpty
                                ? 'Nenhum contato encontrado'
                                : 'Sua lista está vazia',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            query.isNotEmpty
                                ? 'Tente buscar por outro nome ou @usuário.'
                                : 'Toque em "Adicionar contato" para encontrar alguém pelo ID exclusivo ou @usuário.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: secondaryText),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const Divider(indent: 76),
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
