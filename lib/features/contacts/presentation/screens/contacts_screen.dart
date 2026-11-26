import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
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

  Future<void> _copyIdentifier(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label $value copiado!')),
    );
  }

  void _openChat(AppContact contact) {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (myUid == null) return;
    final chatId = ChatIdHelper.buildDirectChatId(myUid, contact.contactUid);
    context.push('/chats/$chatId');
  }

  Future<void> _showEditNicknameDialog(AppContact contact) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _EditNicknameDialog(contact: contact),
    );
    if (updated == null) return;

    try {
      await ref.read(contactsControllerProvider.notifier).updateNickname(
            contactUid: contact.contactUid,
            nickname: updated,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apelido atualizado!')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _confirmRemoveContact(AppContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover contato'),
        content: Text(
          'Remover ${contact.effectiveName} da sua lista de contatos? As conversas existentes não serão apagadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(contactsControllerProvider.notifier)
          .removeContact(contact.contactUid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${contact.effectiveName} removido.')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showContactOptions(AppContact contact) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('Enviar mensagem'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openChat(contact);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar apelido local'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditNicknameDialog(contact);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Remover contato',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmRemoveContact(contact);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myProfile = ref.watch(currentUserProfileProvider).value;
    final contactsAsync = ref.watch(filteredContactsProvider);
    final query = ref.watch(contactsSearchQueryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contatos'),
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
          if (myProfile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/profile'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 20,
                          color: isDark
                              ? AppColors.emeraldBright
                              : AppColors.emeraldDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                myProfile.publicId.isNotEmpty
                                    ? 'Meu ID: ${myProfile.publicId}'
                                    : 'Meu @usuário: @${myProfile.username}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              if (myProfile.publicId.isNotEmpty)
                                Text(
                                  '@${myProfile.username}',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _copyIdentifier(
                            myProfile.publicId.isNotEmpty
                                ? myProfile.publicId
                                : '@${myProfile.username}',
                            myProfile.publicId.isNotEmpty ? 'ID' : '@usuário',
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copiar'),
                        ),
                      ],
                    ),
                  ),
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
                              Icons.people_outline_rounded,
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
                                : 'Para adicionar alguém, toque no botão de adicionar na aba Conversas e informe o ID exclusivo ou @usuário da pessoa.',
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
                        vertical: 4,
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
                          if (contact.hasNickname)
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
                        contact.about.isNotEmpty
                            ? contact.about
                            : '@${contact.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondaryText, fontSize: 13.5),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        onPressed: () => _showContactOptions(contact),
                      ),
                      onTap: () => _openChat(contact),
                      onLongPress: () => _showContactOptions(contact),
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

class _EditNicknameDialog extends StatefulWidget {
  const _EditNicknameDialog({required this.contact});

  final AppContact contact;

  @override
  State<_EditNicknameDialog> createState() => _EditNicknameDialogState();
}

class _EditNicknameDialogState extends State<_EditNicknameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.contact.nickname ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apelido do contato'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nome original: ${widget.contact.displayName} (@${widget.contact.username})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Apelido local',
              hintText: 'Deixe vazio para usar o nome original',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
