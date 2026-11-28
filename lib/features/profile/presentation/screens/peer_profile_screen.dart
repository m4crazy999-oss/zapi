import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/profile_banner.dart';
import '../../../../core/widgets/profile_header_actions.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chats/domain/chat_message.dart';
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
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
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
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isUpdatingContact = false);
    }
  }

  Future<void> _toggleFavorite(AppContact contact, bool value) async {
    if (_isUpdatingContact) return;
    setState(() => _isUpdatingContact = true);
    try {
      await ref.read(contactsControllerProvider.notifier).setFavorite(
            contactUid: contact.contactUid,
            isFavorite: value,
          );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isUpdatingContact = false);
    }
  }

  Future<void> _restoreRemovedContact(
    AppContact contact,
    AppUser targetUser,
  ) async {
    if (_myUid.isEmpty) return;
    try {
      await ref.read(contactsRepositoryProvider).addOrUpdateContact(
            ownerUid: _myUid,
            targetUser: targetUser,
            nickname: contact.nickname,
            isFavorite: contact.isFavorite,
          );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    }
  }

  Future<void> _removeContact(
    AppContact contact,
    AppUser targetUser,
  ) async {
    if (_isUpdatingContact) return;
    setState(() => _isUpdatingContact = true);
    try {
      await ref
          .read(contactsControllerProvider.notifier)
          .removeContact(contact.contactUid);
      if (!mounted) return;
      ZapiToast.showUndo(
        context,
        message: '${contact.effectiveName} removido dos contatos',
        onUndo: () => _restoreRemovedContact(contact, targetUser),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
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
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _isUpdatingBlock = false);
    }
  }

  static final RegExp _linkRegex = RegExp(
    r'(https?://[^\s]+|www\.[^\s]+)',
    caseSensitive: false,
  );

  List<({String url, ChatMessage message})> _extractSharedLinks(
    List<ChatMessage> messages,
  ) {
    final items = <({String url, ChatMessage message})>[];
    for (final msg in messages) {
      if (!msg.isText || msg.text.trim().isEmpty) continue;
      for (final match in _linkRegex.allMatches(msg.text)) {
        final raw = match.group(0)?.trim() ?? '';
        if (raw.isNotEmpty) {
          items.add((url: raw, message: msg));
        }
      }
    }
    return items;
  }

  Future<void> _openSharedMediaMessage(ChatMessage msg) async {
    final mediaId = msg.mediaId?.trim();
    if (mediaId == null || mediaId.isEmpty) {
      if (msg.isImage && (msg.thumbnailBase64?.trim().isNotEmpty ?? false)) {
        _openFullPhoto(
          title: msg.text.trim().isNotEmpty ? msg.text.trim() : 'Foto',
          photoBase64: msg.thumbnailBase64,
        );
      }
      return;
    }

    try {
      final file = await ref.read(mediaCacheServiceProvider).getOrFetchChatMedia(
            chatId: widget.chatId,
            mediaId: mediaId,
            mimeType: msg.mimeType,
            fileName: msg.fileName,
          );
      if (!mounted) return;
      if (file == null) {
        ZapiToast.showInfo(context, 'Mídia não disponível no momento.');
        return;
      }
      if (msg.isImage) {
        final b64 = base64Encode(await file.readAsBytes());
        if (!mounted) return;
        _openFullPhoto(
          title: msg.text.trim().isNotEmpty ? msg.text.trim() : 'Foto',
          photoBase64: b64,
        );
        return;
      }
      final result = await OpenFilex.open(file.path, type: msg.mimeType);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ZapiToast.showInfo(
          context,
          'Nenhum aplicativo encontrado para abrir este arquivo.',
        );
      }
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível abrir esta mídia agora.');
    }
  }

  void _openSharedMediaSheet({
    required List<ChatMessage> mediaItems,
    required List<ChatMessage> fileItems,
    required List<({String url, ChatMessage message})> linkItems,
    int initialTab = 0,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => _SharedMediaSheet(
        mediaItems: mediaItems,
        fileItems: fileItems,
        linkItems: linkItems,
        initialTab: initialTab,
        onOpenMedia: (msg) => _openSharedMediaMessage(msg),
        onCopyLink: (url) async {
          await _copyText(url, 'Link');
          if (sheetCtx.mounted) {
            ZapiToast.showInfo(sheetCtx, 'Link copiado.');
          }
        },
      ),
    );
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
    final rawMessages = ref
            .watch(chatMessagesProvider((chatId: widget.chatId, limit: 100)))
            .value ??
        const <ChatMessage>[];
    final visibleMessages = rawMessages
        .where((m) => !m.deletedForEveryone && !m.isHiddenFor(_myUid))
        .toList();
    final sharedMedia =
        visibleMessages.where((m) => m.isImage || m.isVideo).toList();
    final sharedFiles = visibleMessages.where((m) => m.isFile).toList();
    final sharedLinks = _extractSharedLinks(visibleMessages);

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

    final hideLastSeen = (myUser?.hideLastSeen ?? false) ||
        (peerUser?.hideLastSeen ?? false);
    final statusLabel = hideLastSeen
        ? null
        : (presence.online
            ? 'online agora'
            : DateFormatter.formatLastSeen(
                presence.lastSeen ?? peerUser?.lastSeen,
              ));

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
            child: ProfileHeaderIconPill(
              icon: Icons.arrow_back_rounded,
              onDarkBackdrop: onDarkBackdrop,
              onPressed: () => Navigator.of(context).maybePop(),
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
                padding: const EdgeInsets.only(bottom: 42),
                child: ProfileBanner(
                  bannerBase64: bannerBase64,
                  height: 176 + topPadding,
                ),
              ),
              ZapiAvatar(
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
                if (statusLabel != null) ...[
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.perm_media_rounded,
                          size: 18,
                          color: isDark
                              ? AppColors.emeraldBright
                              : AppColors.emeraldDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mídias, arquivos e links',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: secondaryText,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openSharedMediaSheet(
                            mediaItems: sharedMedia,
                            fileItems: sharedFiles,
                            linkItems: sharedLinks,
                          ),
                          child: Text(
                            '${sharedMedia.length + sharedFiles.length + sharedLinks.length}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in [
                          (
                            icon: Icons.photo_library_rounded,
                            label: '${sharedMedia.length} mídias',
                            tab: 0,
                          ),
                          (
                            icon: Icons.insert_drive_file_rounded,
                            label: '${sharedFiles.length} arquivos',
                            tab: 1,
                          ),
                          (
                            icon: Icons.link_rounded,
                            label: '${sharedLinks.length} links',
                            tab: 2,
                          ),
                        ])
                          Material(
                            color: isDark
                                ? AppColors.darkSurfaceAlt
                                : AppColors.lightSurfaceAlt,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openSharedMediaSheet(
                                mediaItems: sharedMedia,
                                fileItems: sharedFiles,
                                linkItems: sharedLinks,
                                initialTab: item.tab,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 16,
                                      color: isDark
                                          ? AppColors.emeraldBright
                                          : AppColors.emeraldDark,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (sharedMedia.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 66,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              sharedMedia.length > 8 ? 8 : sharedMedia.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final msg = sharedMedia[index];
                            return _MediaThumbTile(
                              message: msg,
                              size: 66,
                              onTap: () => _openSharedMediaMessage(msg),
                            );
                          },
                        ),
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
                    SwitchListTile(
                      secondary: Icon(
                        savedContact.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: savedContact.isFavorite
                            ? const Color(0xFFF59E0B)
                            : null,
                      ),
                      title: const Text('Amigo favorito'),
                      subtitle: const Text(
                        'Destacar e permitir Status privados',
                      ),
                      value: savedContact.isFavorite,
                      onChanged: _isUpdatingContact
                          ? null
                          : (val) => _toggleFavorite(savedContact, val),
                    ),
                    const Divider(height: 1),
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
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  if (savedContact != null) ...[
                    ListTile(
                      enabled: !_isUpdatingContact,
                      leading: const Icon(Icons.person_remove_rounded),
                      title: const Text('Remover dos contatos'),
                      onTap: () =>
                          _removeContact(savedContact, targetForContact),
                    ),
                    const Divider(height: 1),
                  ],
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

class _MediaThumbTile extends StatelessWidget {
  const _MediaThumbTile({
    required this.message,
    required this.size,
    required this.onTap,
  });

  final ChatMessage message;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rawThumb = message.thumbnailBase64?.trim();
    Uint8List? thumbBytes;
    if (rawThumb != null && rawThumb.isNotEmpty) {
      try {
        thumbBytes = base64Decode(
          rawThumb.contains(',') ? rawThumb.split(',').last : rawThumb,
        );
      } catch (_) {}
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbBytes != null)
                Image.memory(
                  thumbBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                )
              else
                Icon(
                  message.isVideo
                      ? Icons.videocam_rounded
                      : Icons.image_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              if (message.isVideo)
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SharedMediaSheet extends StatelessWidget {
  const _SharedMediaSheet({
    required this.mediaItems,
    required this.fileItems,
    required this.linkItems,
    required this.initialTab,
    required this.onOpenMedia,
    required this.onCopyLink,
  });

  final List<ChatMessage> mediaItems;
  final List<ChatMessage> fileItems;
  final List<({String url, ChatMessage message})> linkItems;
  final int initialTab;
  final Future<void> Function(ChatMessage msg) onOpenMedia;
  final Future<void> Function(String url) onCopyLink;

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return DefaultTabController(
          length: 3,
          initialIndex: initialTab.clamp(0, 2),
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Mídias'),
                  Tab(text: 'Arquivos'),
                  Tab(text: 'Links'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    if (mediaItems.isEmpty)
                      const Center(child: Text('Nenhuma foto ou vídeo ainda.'))
                    else
                      GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: mediaItems.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final msg = mediaItems[index];
                          return _MediaThumbTile(
                            message: msg,
                            size: double.infinity,
                            onTap: () => onOpenMedia(msg),
                          );
                        },
                      ),
                    if (fileItems.isEmpty)
                      const Center(child: Text('Nenhum arquivo ainda.'))
                    else
                      ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: fileItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final msg = fileItems[index];
                          final sizeLabel = _formatBytes(msg.sizeBytes);
                          final timeLabel = DateFormatter.formatTime(
                            msg.effectiveTime,
                          );
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.insert_drive_file_rounded),
                            ),
                            title: Text(
                              msg.fileName ?? 'Arquivo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              sizeLabel.isNotEmpty
                                  ? '$sizeLabel • $timeLabel'
                                  : timeLabel,
                            ),
                            trailing: const Icon(Icons.open_in_new_rounded),
                            onTap: () => onOpenMedia(msg),
                          );
                        },
                      ),
                    if (linkItems.isEmpty)
                      const Center(child: Text('Nenhum link encontrado.'))
                    else
                      ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: linkItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = linkItems[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.link_rounded),
                            ),
                            title: Text(
                              entry.url,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              DateFormatter.formatTime(
                                entry.message.effectiveTime,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy_rounded),
                              tooltip: 'Copiar link',
                              onPressed: () => onCopyLink(entry.url),
                            ),
                            onTap: () => onCopyLink(entry.url),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
