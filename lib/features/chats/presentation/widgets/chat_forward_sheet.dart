import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../providers/chats_providers.dart';

class ForwardTarget {
  const ForwardTarget({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.about,
    required this.photoBase64,
    required this.photoUrl,
    required this.chatExists,
  });

  final String uid;
  final String displayName;
  final String username;
  final String about;
  final String? photoBase64;
  final String? photoUrl;
  final bool chatExists;
}

Future<ForwardTarget?> showChatForwardSheet({
  required BuildContext context,
  required String myUid,
}) {
  return showModalBottomSheet<ForwardTarget>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) {
      var filter = '';
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Consumer(
            builder: (context, sheetRef, _) {
              final chats = sheetRef.watch(userChatsProvider).value ?? const [];
              final contacts =
                  sheetRef.watch(contactsListProvider).value ?? const [];
              final contactsByUid = sheetRef.watch(contactsByUidProvider);
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final secondaryText = isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary;

              final items = <ForwardTarget>[];
              final seenUids = <String>{};

              for (final chat in chats) {
                final peerUid = chat.otherParticipantUid(myUid);
                if (peerUid.isEmpty || !seenUids.add(peerUid)) continue;
                final saved = contactsByUid[peerUid];
                final profile = chat.profileFor(peerUid);
                items.add(
                  ForwardTarget(
                    uid: peerUid,
                    displayName: saved?.effectiveName ??
                        profile?.displayName ??
                        'Contato Zapi',
                    username: saved?.username ?? profile?.username ?? '',
                    about: saved?.about ?? profile?.about ?? '',
                    photoBase64: saved?.photoBase64 ?? profile?.photoBase64,
                    photoUrl: saved?.photoUrl ?? profile?.photoUrl,
                    chatExists: true,
                  ),
                );
              }

              for (final contact in contacts) {
                if (!seenUids.add(contact.contactUid)) continue;
                items.add(
                  ForwardTarget(
                    uid: contact.contactUid,
                    displayName: contact.effectiveName,
                    username: contact.username,
                    about: contact.about,
                    photoBase64: contact.photoBase64,
                    photoUrl: contact.photoUrl,
                    chatExists: false,
                  ),
                );
              }

              final q = filter.trim().toLowerCase();
              final filtered = q.isEmpty
                  ? items
                  : items
                      .where(
                        (item) =>
                            item.displayName.toLowerCase().contains(q) ||
                            item.username.toLowerCase().contains(q),
                      )
                      .toList();

              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: Text(
                          'Encaminhar para...',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: TextField(
                          onChanged: (val) =>
                              setSheetState(() => filter = val),
                          decoration: const InputDecoration(
                            hintText: 'Buscar conversa ou contato...',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Nenhum contato disponível.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: secondaryText),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(indent: 72, height: 1),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return ListTile(
                                    leading: ZapiAvatar(
                                      displayName: item.displayName,
                                      photoBase64: item.photoBase64,
                                      photoUrl: item.photoUrl,
                                      radius: 21,
                                    ),
                                    title: Text(
                                      item.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: item.username.isNotEmpty
                                        ? Text(
                                            '@${item.username}',
                                            style: TextStyle(
                                              color: secondaryText,
                                              fontSize: 12.5,
                                            ),
                                          )
                                        : null,
                                    onTap: () => Navigator.pop(sheetCtx, item),
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
    },
  );
}
