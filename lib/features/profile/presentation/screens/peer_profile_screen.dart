import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/profile_banner.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chats/presentation/providers/chats_providers.dart';
import '../../../contacts/domain/app_contact.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../providers/profile_providers.dart';

class PeerProfileScreen extends ConsumerStatefulWidget {
  const PeerProfileScreen({
    super.key,
    required this.chatId,
  });

  final String chatId;

  @override
  ConsumerState<PeerProfileScreen> createState() => _PeerProfileScreenState();
}

class _PeerProfileScreenState extends ConsumerState<PeerProfileScreen> {
  bool _isUpdatingContact = false;
  bool _isUpdatingBlock = false;

  String get _myUid => ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  String get _peerUid {
    final parts = widget.chatId.split('_');
    if (parts.length == 2) {
      return parts[0] == _myUid ? parts[1] : parts[0];
    }
    return '';
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado!')),
    );
  }

  void _openFullPhoto({
    required String title,
    String? photoBase64,
    String? photoUrl,
  }) {
    final cleanB64 = photoBase64?.trim();
    if ((cleanB64 == null || cleanB64.isEmpty) &&
        (photoUrl == null || photoUrl.trim().isEmpty)) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: (cleanB64 != null && cleanB64.isNotEmpty)
                  ? Image.memory(
                      base64Decode(
                        cleanB64.contains(',')
                            ? cleanB64.split(',').last
                            : cleanB64,
                      ),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  : Image.network(photoUrl!, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogCtx),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToContacts(AppUser targetUser) async {
    if (_isUpdatingContact) return;
    setState(() => _isUpdatingContact = true);
    try {
      await ref
          .read(contactsControllerProvider.notifier)
          .addContact(targetUser: targetUser);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${targetUser.displayName} adicionado aos contatos!'),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingContact = false);
    }
  }

  Future<void> _editNickname(AppContact contact) async {
    final controller = TextEditingController(text: contact.nickname ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Apelido do contato'),
        content: TextField(
          controller: controller,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Apelido local',
            hintText: 'Deixe vazio para usar o nome original',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null) return;

    setState(() => _isUpdatingContact = true);
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
    } finally {
      if (mounted) setState(() => _isUpdatingContact = false);
    }
  }

  Future<void> _removeContact(AppContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover contato'),
        content: Text(
          'Remover ${contact.effectiveName} da sua lista? A conversa continua disponível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isUpdatingContact = true);
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
    } finally {
      if (mounted) setState(() => _isUpdatingContact = false);
    }
  }

  Future<void> _toggleBlock({
    required String peerName,
    required bool currentlyBlocked,
  }) async {
    if (_isUpdatingBlock || _myUid.isEmpty || _peerUid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(currentlyBlocked ? 'Desbloquear pessoa' : 'Bloquear pessoa'),
        content: Text(
          currentlyBlocked
              ? 'Permitir que $peerName envie mensagens para você novamente?'
              : '$peerName não poderá mais enviar mensagens para você até que seja desbloqueado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: currentlyBlocked
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(currentlyBlocked ? 'Desbloquear' : 'Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isUpdatingBlock = true);
    try {
      await ref.read(chatsRepositoryProvider).setUserBlocked(
            currentUid: _myUid,
            peerUid: _peerUid,
            chatId: widget.chatId,
            blocked: !currentlyBlocked,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyBlocked
                ? '$peerName foi desbloqueado.'
                : '$peerName foi bloqueado.',
          ),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingBlock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerUid = _peerUid;
    final myUser = ref.watch(currentUserProfileProvider).value;
    final peerUser = ref.watch(peerUserProfileProvider(peerUid)).value;
    final thread = ref.watch(chatThreadProvider(widget.chatId)).value;
    final savedContact = ref.watch(contactsByUidProvider)[peerUid];
    final presence = ref.watch(userPresenceProvider(peerUid)).value ??
        UserPresence.offline;
    final isMuted = ref.watch(chatPreferencesProvider).isMuted(widget.chatId);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final threadProfile = thread?.profileFor(peerUid);
    final displayName = savedContact?.effectiveName ??
        peerUser?.displayName ??
        threadProfile?.displayName ??
        'Usuário Zapi';
    final username = peerUser?.username ??
        savedContact?.username ??
        threadProfile?.username ??
        '';
    final about = (peerUser?.about.trim().isNotEmpty ?? false)
        ? peerUser!.about.trim()
        : ((savedContact?.about.trim().isNotEmpty ?? false)
            ? savedContact!.about.trim()
            : (threadProfile?.about?.trim() ?? ''));
    final publicId = peerUser?.publicId ?? '';
    final bannerBase64 = peerUser?.bannerBase64;
    final photoBase64 = peerUser?.photoBase64 ??
        savedContact?.photoBase64 ??
        threadProfile?.photoBase64;
    final photoUrl = peerUser?.photoUrl ??
        savedContact?.photoUrl ??
        threadProfile?.photoUrl;

    final isBlockedByMe =
        (myUser?.blockedUids.contains(peerUid) ?? false) ||
            (thread?.isBlockedBy(_myUid) ?? false);

    final statusLabel = presence.online
        ? 'online agora'
        : DateFormatter.formatLastSeen(presence.lastSeen ?? peerUser?.lastSeen);

    final targetForContact = peerUser ??
        AppUser(
          uid: peerUid,
          displayName: displayName,
          username: username,
          about: about,
          photoBase64: photoBase64,
          photoUrl: photoUrl,
        );

    final hasCustomBanner =
        bannerBase64 != null && bannerBase64.trim().isNotEmpty;
    final topPadding = MediaQuery.paddingOf(context).top;
    final onDarkBackdrop = hasCustomBanner || isDark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: Material(
              color: onDarkBackdrop
                  ? Colors.black.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.78),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: onDarkBackdrop
                        ? Colors.white
                        : AppColors.lightTextPrimary,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: ProfileBanner(
                  bannerBase64: bannerBase64,
                  height: 236 + topPadding,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: ZapiAvatar(
                  displayName: displayName,
                  photoBase64: photoBase64,
                  photoUrl: photoUrl,
                  radius: 50,
                  onTap: () => _openFullPhoto(
                    title: displayName,
                    photoBase64: photoBase64,
                    photoUrl: photoUrl,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (savedContact != null && savedContact.hasNickname) ...[
                  const SizedBox(height: 2),
                  Text(
                    savedContact.displayName,
                    style: TextStyle(fontSize: 13, color: secondaryText),
                  ),
                ],
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '@$username',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.emeraldBright
                          : AppColors.emeraldDark,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        presence.online ? FontWeight.w600 : FontWeight.w400,
                    color: presence.online
                        ? (isDark
                            ? AppColors.emeraldBright
                            : AppColors.emeraldDark)
                        : secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          size: 18,
                          color: isDark
                              ? AppColors.emeraldBright
                              : AppColors.emeraldDark,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recado',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      about.isNotEmpty ? about : AppConstants.defaultAbout,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                    ),
                    if (publicId.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 18,
                            color: secondaryText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ID: $publicId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _copyText(publicId, 'ID'),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copiar'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(
                      isMuted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_active_rounded,
                    ),
                    title: const Text('Silenciar notificações'),
                    subtitle: const Text(
                      'Não exibir avisos desta conversa',
                    ),
                    value: isMuted,
                    onChanged: (val) => ref
                        .read(chatPreferencesProvider.notifier)
                        .setChatMuted(widget.chatId, val),
                  ),
                  const Divider(height: 1),
                  if (savedContact == null)
                    ListTile(
                      enabled: !_isUpdatingContact,
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: const Text('Adicionar aos contatos'),
                      trailing: _isUpdatingContact
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () => _addToContacts(targetForContact),
                    )
                  else ...[
                    ListTile(
                      enabled: !_isUpdatingContact,
                      leading: const Icon(Icons.edit_rounded),
                      title: const Text('Editar apelido'),
                      subtitle: savedContact.hasNickname
                          ? Text('Atual: ${savedContact.nickname}')
                          : null,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editNickname(savedContact),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: !_isUpdatingContact,
                      leading: const Icon(Icons.person_remove_rounded),
                      title: const Text('Remover dos contatos'),
                      onTap: () => _removeContact(savedContact),
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    enabled: !_isUpdatingBlock,
                    leading: Icon(
                      isBlockedByMe
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      isBlockedByMe
                          ? 'Desbloquear $displayName'
                          : 'Bloquear $displayName',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _toggleBlock(
                      peerName: displayName,
                      currentlyBlocked: isBlockedByMe,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
