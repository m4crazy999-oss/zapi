import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../domain/status_item.dart';

class StatusPrivacyScreen extends ConsumerWidget {
  const StatusPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(chatPreferencesProvider);
    final contactsAsync = ref.watch(contactsListProvider);
    final contacts = contactsAsync.value ?? const [];
    final currentMode = StatusPrivacyMode.fromCode(prefs.statusPrivacyMode);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final favoriteCount = contacts.where((c) => c.isFavorite).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacidade do status'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Quem pode ver seus novos status',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'A escolha é aplicada aos novos status que você publicar. Cada status some após 24 horas.',
            style: TextStyle(fontSize: 13, color: secondaryText),
          ),
          const SizedBox(height: 12),
          Card(
            child: RadioGroup<StatusPrivacyMode>(
              groupValue: currentMode,
              onChanged: (mode) {
                if (mode == null) return;
                ref.read(chatPreferencesProvider.notifier).setStatusPrivacy(
                      mode: mode.code,
                    );
              },
              child: Column(
                children: [
                  RadioListTile<StatusPrivacyMode>(
                    value: StatusPrivacyMode.all,
                    title: const Text('Todos os contatos'),
                    subtitle: Text(
                      contacts.isEmpty
                          ? 'Todos da sua lista de contatos'
                          : '${contacts.length} contato${contacts.length == 1 ? '' : 's'} na sua agenda',
                    ),
                  ),
                  const Divider(height: 1),
                  RadioListTile<StatusPrivacyMode>(
                    value: StatusPrivacyMode.favorites,
                    title: const Text('Amigos favoritos'),
                    subtitle: Text(
                      favoriteCount == 0
                          ? 'Nenhum amigo favorito marcado ainda'
                          : '$favoriteCount amigo${favoriteCount == 1 ? '' : 's'} favorito${favoriteCount == 1 ? '' : 's'}',
                    ),
                  ),
                  const Divider(height: 1),
                  RadioListTile<StatusPrivacyMode>(
                    value: StatusPrivacyMode.custom,
                    title: const Text('Contatos selecionados'),
                    subtitle: Text(
                      prefs.statusCustomUids.isEmpty
                          ? 'Escolha exatamente quem verá seus status'
                          : '${prefs.statusCustomUids.length} selecionado${prefs.statusCustomUids.length == 1 ? '' : 's'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  currentMode == StatusPrivacyMode.custom
                      ? 'Selecionar contatos para o status'
                      : 'Amigos favoritos',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (currentMode != StatusPrivacyMode.custom && favoriteCount > 0)
                Text(
                  '$favoriteCount',
                  style: const TextStyle(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentMode == StatusPrivacyMode.custom
                ? 'Marque abaixo os contatos que poderão ver seus status.'
                : 'Toque na estrela para definir seus amigos favoritos para o status.',
            style: TextStyle(fontSize: 13, color: secondaryText),
          ),
          const SizedBox(height: 10),
          if (contactsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (contacts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Você ainda não adicionou contatos na sua agenda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < contacts.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    if (currentMode == StatusPrivacyMode.custom)
                      CheckboxListTile(
                        value: prefs.statusCustomUids.contains(
                          contacts[i].contactUid,
                        ),
                        secondary: ZapiAvatar(
                          displayName: contacts[i].effectiveName,
                          photoBase64: contacts[i].photoBase64,
                          photoUrl: contacts[i].photoUrl,
                          radius: 20,
                        ),
                        title: Text(
                          contacts[i].effectiveName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '@${contacts[i].username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (checked) {
                          final next = Set<String>.from(prefs.statusCustomUids);
                          if (checked == true) {
                            next.add(contacts[i].contactUid);
                          } else {
                            next.remove(contacts[i].contactUid);
                          }
                          ref
                              .read(chatPreferencesProvider.notifier)
                              .setStatusPrivacy(
                                mode: StatusPrivacyMode.custom.code,
                                customUids: next,
                              );
                        },
                      )
                    else
                      ListTile(
                        leading: ZapiAvatar(
                          displayName: contacts[i].effectiveName,
                          photoBase64: contacts[i].photoBase64,
                          photoUrl: contacts[i].photoUrl,
                          radius: 20,
                        ),
                        title: Text(
                          contacts[i].effectiveName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '@${contacts[i].username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: contacts[i].isFavorite
                              ? 'Remover dos amigos favoritos'
                              : 'Marcar como amigo favorito',
                          onPressed: () {
                            ref
                                .read(contactsControllerProvider.notifier)
                                .setFavorite(
                                  contactUid: contacts[i].contactUid,
                                  isFavorite: !contacts[i].isFavorite,
                                );
                          },
                          icon: Icon(
                            contacts[i].isFavorite
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: contacts[i].isFavorite
                                ? const Color(0xFFF59E0B)
                                : secondaryText,
                          ),
                        ),
                        onTap: () {
                          ref
                              .read(contactsControllerProvider.notifier)
                              .setFavorite(
                                contactUid: contacts[i].contactUid,
                                isFavorite: !contacts[i].isFavorite,
                              );
                        },
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
