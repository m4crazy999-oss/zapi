import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_text_field.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/contacts_providers.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _searchController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _searching = false;
  bool _saving = false;
  String? _searchError;
  AppUser? _foundUser;

  @override
  void dispose() {
    _searchController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _foundUser = null;
    });

    try {
      final user = await ref
          .read(contactsControllerProvider.notifier)
          .searchUser(_searchController.text);
      if (!mounted) return;
      setState(() => _foundUser = user);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _searchError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Não foi possível buscar este contato. Verifique sua conexão.';
      });
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _confirmAdd(AppUser targetUser) async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref.read(contactsControllerProvider.notifier).addContact(
            targetUser: targetUser,
            nickname: _nicknameController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${targetUser.displayName} adicionado! Acesse a aba Contatos para enviar mensagem.',
          ),
        ),
      );
      context.pop();
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingContacts = ref.watch(contactsByUidProvider);
    final myUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final found = _foundUser;
    final alreadySaved =
        found != null && existingContacts.containsKey(found.uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar contato por ID')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Digite o ID exclusivo (ex.: ZP-4K8M9P2X) ou o @usuário da pessoa para adicioná-la aos seus contatos.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: secondaryText),
                  ),
                  const SizedBox(height: 16),
                  ZapiTextField(
                    controller: _searchController,
                    label: 'ID ou @usuário',
                    hint: 'ex: ZP-4K8M9P2X ou @ana.paula',
                    prefixIcon: Icons.person_search_rounded,
                    textInputAction: TextInputAction.search,
                    enabled: !_searching && !_saving,
                    onFieldSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_searching || _saving) ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(_searching ? 'Buscando...' : 'Buscar perfil'),
                  ),
                  if (_searchError != null) ...[
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _searchError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (found != null) ...[
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            ZapiAvatar(
                              displayName: found.displayName,
                              photoBase64: found.photoBase64,
                              photoUrl: found.photoUrl,
                              radius: 42,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              found.displayName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${found.username}',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.emeraldBright
                                    : AppColors.emeraldDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (found.publicId.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${found.publicId}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (found.about.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                found.about,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: secondaryText),
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (alreadySaved) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.emerald.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Este usuário já está na sua lista de contatos.',
                                  style: TextStyle(
                                    color: AppColors.emeraldDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (myUid != null)
                                FilledButton.icon(
                                  onPressed: () {
                                    final chatId = ChatIdHelper.buildDirectChatId(
                                      myUid,
                                      found.uid,
                                    );
                                    context.pushReplacement('/chats/$chatId');
                                  },
                                  icon: const Icon(Icons.chat_rounded),
                                  label: const Text('Abrir conversa'),
                                ),
                            ] else ...[
                              ZapiTextField(
                                controller: _nicknameController,
                                label: 'Apelido local (opcional)',
                                hint: 'Como você deseja ver esse contato',
                                prefixIcon: Icons.badge_outlined,
                                enabled: !_saving,
                                maxLength: 50,
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed:
                                    _saving ? null : () => _confirmAdd(found),
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.person_add_alt_1_rounded),
                                label: Text(
                                  _saving
                                      ? 'Salvando...'
                                      : 'Confirmar e adicionar',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
