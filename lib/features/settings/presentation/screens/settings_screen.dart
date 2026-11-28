import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/app_update_service.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/services/media_cache_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/chat_id_helper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/chat_wallpaper.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chats/domain/chat_thread.dart';
import '../../../chats/presentation/providers/chats_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../widgets/app_lock_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _notificationsEnabled = true;
  bool _backgroundModeEnabled = true;
  bool _ignoringBattery = true;
  int? _cacheBytes;
  bool _isClearingCache = false;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationStatus();
    _refreshCacheSize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationStatus();
      _refreshCacheSize();
    }
  }

  Future<void> _refreshCacheSize() async {
    final bytes =
        await ref.read(mediaCacheServiceProvider).computeCacheSizeBytes();
    if (mounted) {
      setState(() => _cacheBytes = bytes);
    }
  }

  String _formatCacheSize(int? bytes) {
    if (bytes == null) return 'Calculando...';
    if (bytes <= 0) return '0 KB em uso';
    if (bytes < 1024) return '$bytes B em uso';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB em uso';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB em uso';
  }

  Future<void> _confirmClearCache() async {
    if (_isClearingCache) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Limpar cache de mídia'),
        content: const Text(
          'Os arquivos temporários de fotos, vídeos e áudios salvos no aparelho serão apagados. Você poderá baixá-los novamente nas conversas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Limpar agora'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isClearingCache = true);
    try {
      await ref.read(mediaCacheServiceProvider).clearAllCache();
      await _refreshCacheSize();
      if (!mounted) return;
      ZapiToast.showInfo(context, 'Cache limpo com sucesso.');
    } finally {
      if (mounted) {
        setState(() => _isClearingCache = false);
      }
    }
  }

  Future<void> _checkForUpdatesManually() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final service = ref.read(appUpdateServiceProvider);
      final update = await service.checkForUpdate(throwOnError: true);
      if (!mounted) return;
      if (update != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UpdateRequiredScreen(
              update: update,
              updateService: service,
            ),
          ),
        );
      } else {
        ZapiToast.showInfo(context, 'Você já está na versão mais recente.');
      }
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível verificar atualizações agora.',
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  void _showWhatsNewSheet(String versionLabel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.emeraldBright : AppColors.emeraldDark;
    const highlights = [
      (
        icon: Icons.graphic_eq_rounded,
        title: 'Áudio e gravação renovados',
        body:
            'Pausa instantânea com barra compacta no topo, preview antes de enviar e envio rápido para outras conversas.',
      ),
      (
        icon: Icons.palette_rounded,
        title: 'Editor de fotos e Status avançados',
        body:
            'Filtros de cor, ajuste de brilho, texto arrastável com rotação e escala sobre foto de fundo e anel segmentado no Status.',
      ),
      (
        icon: Icons.tune_rounded,
        title: 'Mais controle e privacidade',
        body:
            'Escolha quem pode te adicionar, oculte prévias nas notificações, personalize a cor de destaque e gerencie o cache local.',
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'O que há de novo (v$versionLabel)',
                style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              ...highlights.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: accent.withValues(alpha: 0.14),
                        child: Icon(item.icon, size: 19, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.body,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(sheetCtx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshNotificationStatus() async {
    final service = ref.read(notificationServiceProvider);
    final enabled = await service.areNotificationsEnabled();
    final bgEnabled = await service.isBackgroundModeEnabled();
    final ignoringBattery = await service.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _backgroundModeEnabled = bgEnabled;
        _ignoringBattery = ignoringBattery;
      });
    }
  }

  Future<void> _handleNotificationsTap() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermissionIfNeeded();
    if (granted) {
      await _refreshNotificationStatus();
      return;
    }

    await openAppSettings();
  }

  Future<void> _toggleBackgroundMode(bool value) async {
    setState(() => _backgroundModeEnabled = value);
    await ref.read(notificationServiceProvider).setBackgroundModeEnabled(value);
  }

  Future<void> _requestBatteryExemption() async {
    await ref
        .read(notificationServiceProvider)
        .requestIgnoreBatteryOptimizations();
  }

  Future<void> _setShowLastSeen(bool visible) async {
    try {
      final hide = !visible;
      await ref
          .read(profileControllerProvider.notifier)
          .updatePrivacy(hideLastSeen: hide);
      await ref.read(presenceServiceProvider).setHideLastSeen(hide);
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível atualizar sua privacidade agora.',
      );
    }
  }

  Future<void> _setShowReadReceipts(bool visible) async {
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .updatePrivacy(hideReadReceipts: !visible);
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível atualizar sua privacidade agora.',
      );
    }
  }

  String _addPrivacyLabel(String value) => switch (value) {
        'idOnly' => 'Somente meu ID exclusivo',
        'usernameOnly' => 'Somente meu @usuário',
        _ => 'Todos (@usuário e ID)',
      };

  Future<void> _openAddPrivacyPicker(String currentValue) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        const options = [
          (
            value: 'all',
            title: 'Todos (@usuário e ID)',
            subtitle: 'Qualquer pessoa pode te encontrar pelo @ ou pelo ID.',
          ),
          (
            value: 'idOnly',
            title: 'Somente meu ID exclusivo',
            subtitle: 'Apenas quem tiver seu código ZP-... consegue te adicionar.',
          ),
          (
            value: 'usernameOnly',
            title: 'Somente meu @usuário',
            subtitle: 'Busca liberada apenas pelo seu @usuário público.',
          ),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Quem pode me adicionar',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              ...options.map(
                (opt) => RadioListTile<String>(
                  value: opt.value,
                  groupValue: currentValue,
                  title: Text(opt.title),
                  subtitle: Text(opt.subtitle),
                  onChanged: (val) => Navigator.pop(sheetCtx, val),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == currentValue) return;
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .updatePrivacy(addPrivacy: picked);
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível atualizar esta preferência agora.',
      );
    }
  }

  Future<void> _openBlockedContactsSheet(List<String> blockedUids) async {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final currentBlocked =
                sheetRef.watch(currentUserProfileProvider).value?.blockedUids ??
                    blockedUids;
            final contactsByUid = sheetRef.watch(contactsByUidProvider);

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Text(
                      'Contatos bloqueados',
                      style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (currentBlocked.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Text(
                        'Nenhum contato bloqueado no momento.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: currentBlocked.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final blockedUid = currentBlocked[index];
                          final contact = contactsByUid[blockedUid];
                          final peer = sheetRef
                              .watch(peerUserProfileProvider(blockedUid))
                              .value;
                          final label = contact?.effectiveName ??
                              peer?.displayName ??
                              'Usuário Zapi';
                          final sub = (peer?.username.isNotEmpty ?? false)
                              ? '@${peer!.username}'
                              : ((contact?.username.isNotEmpty ?? false)
                                  ? '@${contact!.username}'
                                  : '');
                          return ListTile(
                            leading: ZapiAvatar(
                              displayName: label,
                              photoBase64:
                                  peer?.photoBase64 ?? contact?.photoBase64,
                              photoUrl: peer?.photoUrl ?? contact?.photoUrl,
                              radius: 20,
                            ),
                            title: Text(label),
                            subtitle: sub.isNotEmpty ? Text(sub) : null,
                            trailing: TextButton(
                              onPressed: myUid.isEmpty
                                  ? null
                                  : () async {
                                      try {
                                        await sheetRef
                                            .read(chatsRepositoryProvider)
                                            .setUserBlocked(
                                              currentUid: myUid,
                                              peerUid: blockedUid,
                                              chatId: ChatIdHelper
                                                  .buildDirectChatId(
                                                myUid,
                                                blockedUid,
                                              ),
                                              blocked: false,
                                            );
                                      } on AppException catch (e) {
                                        if (sheetCtx.mounted) {
                                          ZapiToast.showError(
                                            sheetCtx,
                                            e.message,
                                          );
                                        }
                                      }
                                    },
                              child: const Text('Desbloquear'),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openArchivedChatsSheet() async {
    final myUid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final archivedIds =
                sheetRef.watch(chatPreferencesProvider).archivedChatIds;
            final allChats =
                sheetRef.watch(userChatsProvider).value ?? const <ChatThread>[];
            final archivedChats = allChats
                .where((c) => archivedIds.contains(c.chatId))
                .toList();
            final contactsByUid = sheetRef.watch(contactsByUidProvider);

            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Text(
                      'Conversas arquivadas',
                      style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (archivedChats.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Text(
                        'Nenhuma conversa arquivada no momento.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: archivedChats.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final thread = archivedChats[index];
                          final peerUid = thread.otherParticipantUid(myUid);
                          final contact = contactsByUid[peerUid];
                          final profile = thread.profileFor(peerUid);
                          final name = contact?.effectiveName ??
                              profile?.displayName ??
                              'Conversa';
                          return ListTile(
                            leading: ZapiAvatar(
                              displayName: name,
                              photoBase64:
                                  contact?.photoBase64 ?? profile?.photoBase64,
                              photoUrl: contact?.photoUrl ?? profile?.photoUrl,
                              radius: 20,
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: thread.lastMessage.trim().isNotEmpty
                                ? Text(
                                    thread.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            trailing: TextButton(
                              onPressed: () => sheetRef
                                  .read(chatPreferencesProvider.notifier)
                                  .setChatArchived(thread.chatId, false),
                              child: const Text('Desarquivar'),
                            ),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              context.push('/chat/${thread.chatId}');
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _autoDownloadLabel(String mode) => switch (mode) {
        'wifi' => 'Somente no Wi-Fi',
        'never' => 'Nunca (baixar sob demanda)',
        _ => 'Sempre (Wi-Fi e dados móveis)',
      };

  Future<void> _openAutoDownloadPicker(String currentValue) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        const options = [
          (
            value: 'always',
            title: 'Sempre (Wi-Fi e dados móveis)',
            subtitle: 'Baixa mídias recebidas automaticamente.',
          ),
          (
            value: 'wifi',
            title: 'Somente no Wi-Fi',
            subtitle: 'Economiza seu plano de dados móveis.',
          ),
          (
            value: 'never',
            title: 'Nunca (sob demanda)',
            subtitle: 'Baixa somente quando você tocar na mídia.',
          ),
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Download automático de mídia',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              ...options.map(
                (opt) => RadioListTile<String>(
                  value: opt.value,
                  groupValue: currentValue,
                  title: Text(opt.title),
                  subtitle: Text(opt.subtitle),
                  onChanged: (val) => Navigator.pop(sheetCtx, val),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await ref
        .read(chatPreferencesProvider.notifier)
        .setAutoDownloadMedia(picked);
  }

  Future<void> _openWallpaperPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Consumer(
          builder: (context, sheetRef, _) {
            final selected = sheetRef.watch(chatWallpaperProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fundo das conversas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ChatWallpaperPreset.all.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                      ),
                      itemBuilder: (context, index) {
                        final preset = ChatWallpaperPreset.all[index];
                        return ChatWallpaperSwatch(
                          preset: preset,
                          selected: preset.id == selected.id,
                          onTap: () {
                            sheetRef
                                .read(appearanceProvider.notifier)
                                .setWallpaper(preset.id);
                            Navigator.pop(sheetCtx);
                          },
                        );
                      },
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

  Future<void> _openChangePasswordDialog() async {
    final result = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onForgotPassword: _sendResetLinkToMyEmail,
      ),
    );
    if (result == null) return;

    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: result.current,
            newPassword: result.next,
          );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível alterar sua senha agora.');
    }
  }

  Future<void> _sendResetLinkToMyEmail() async {
    final email = ref.read(privateAccountEmailProvider).value?.trim() ??
        ref.read(firebaseAuthProvider).currentUser?.email?.trim() ??
        '';

    if (email.isEmpty) {
      if (mounted) {
        context.push('/forgot-password');
      }
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
      if (!mounted) return;
      ZapiToast.showInfo(
        context,
        'Link de recuperação enviado para $email (confira também o Spam).',
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível enviar o link de recuperação.',
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair da conta'),
        content: const Text(
          'Você poderá entrar novamente a qualquer momento com seu e-mail e senha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível sair da conta agora.');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmedPassword = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (confirmedPassword == null || confirmedPassword.isEmpty) return;

    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(confirmedPassword);
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível excluir sua conta agora.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final currentUser = profileAsync.value;
    final privateEmail = ref.watch(privateAccountEmailProvider).value ??
        ref.watch(firebaseAuthProvider).currentUser?.email ??
        '';
    final versionLabel =
        ref.watch(appVersionLabelProvider).value ?? '1.0.0';
    final themeMode = ref.watch(themeModeProvider);
    final wallpaper = ref.watch(chatWallpaperProvider);
    final selectedAccent = ref.watch(accentPresetProvider);
    final chatPrefs = ref.watch(chatPreferencesProvider);
    final allChats =
        ref.watch(userChatsProvider).value ?? const <ChatThread>[];
    final archivedCount = allChats
        .where((c) => chatPrefs.archivedChatIds.contains(c.chatId))
        .length;
    final isAuthBusy = ref.watch(authControllerProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accent = isDark
        ? selectedAccent.primaryDark
        : selectedAccent.secondaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              profileAsync.when(
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (_, __) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: const Text('Meu perfil'),
                    subtitle: const Text('Toque para editar seus dados e ID'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/profile'),
                  ),
                ),
                data: (user) {
                  if (user == null) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_rounded),
                        title: const Text('Concluir perfil'),
                        subtitle: const Text(
                          'Toque para finalizar seu perfil e gerar seu ID.',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/profile'),
                      ),
                    );
                  }
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/profile'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            ZapiAvatar(
                              displayName: user.displayName,
                              photoBase64: user.photoBase64,
                              photoUrl: user.photoUrl,
                              radius: 28,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${user.username}',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  if (user.about.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      user.about.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: secondaryText,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: secondaryText,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // 1. CONTA
              _SectionTitle(label: 'Conta', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.alternate_email_rounded, color: accent),
                      title: const Text('E-mail da conta'),
                      subtitle: Text(
                        privateEmail.isNotEmpty
                            ? '$privateEmail (visível só para você)'
                            : 'Visível apenas para você',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: !isAuthBusy,
                      leading: Icon(Icons.password_rounded, color: accent),
                      title: const Text('Alterar senha'),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: _openChangePasswordDialog,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: !isAuthBusy,
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Sair da conta'),
                      onTap: _confirmSignOut,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: !isAuthBusy,
                      leading: Icon(
                        Icons.delete_forever_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Excluir minha conta',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _confirmDeleteAccount,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. PRIVACIDADE E SEGURANÇA
              _SectionTitle(
                label: 'Privacidade e segurança',
                color: secondaryText,
              ),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(Icons.visibility_rounded, color: accent),
                      title: const Text('Visto por último e online'),
                      subtitle: const Text(
                        'Mostra quando você está online ou ativo recentemente.',
                      ),
                      value: !(currentUser?.hideLastSeen ?? false),
                      onChanged: currentUser == null ? null : _setShowLastSeen,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.done_all_rounded, color: accent),
                      title: const Text('Confirmação de leitura'),
                      subtitle: const Text(
                        'Envia e exibe quando as mensagens foram lidas.',
                      ),
                      value: !(currentUser?.hideReadReceipts ?? false),
                      onChanged:
                          currentUser == null ? null : _setShowReadReceipts,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: currentUser != null,
                      leading: Icon(Icons.person_search_rounded, color: accent),
                      title: const Text('Quem pode me adicionar'),
                      subtitle: Text(
                        _addPrivacyLabel(currentUser?.addPrivacy ?? 'all'),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: currentUser == null
                          ? null
                          : () => _openAddPrivacyPicker(currentUser.addPrivacy),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.lock_rounded, color: accent),
                      title: const Text('Bloqueio do app'),
                      subtitle: Text(
                        chatPrefs.hasAppLockConfigured
                            ? (chatPrefs.appLockUseDeviceBiometric
                                ? 'Ativo com PIN e biometria'
                                : 'Ativo com PIN de 4 dígitos')
                            : 'Desativado',
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: () => AppLockSheet.show(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.block_rounded, color: accent),
                      title: const Text('Contatos bloqueados'),
                      subtitle: Text(
                        (currentUser?.blockedUids.isEmpty ?? true)
                            ? 'Nenhum contato bloqueado'
                            : '${currentUser!.blockedUids.length} bloqueado(s)',
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: () => _openBlockedContactsSheet(
                        currentUser?.blockedUids ?? const [],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. CONVERSAS
              _SectionTitle(label: 'Conversas', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.wallpaper_rounded, color: accent),
                      title: const Text('Fundo das conversas'),
                      subtitle: Text(wallpaper.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: wallpaper.previewAccent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: secondaryText,
                          ),
                        ],
                      ),
                      onTap: _openWallpaperPicker,
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_size_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Tamanho da fonte nas mensagens',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: 'small',
                                  label: Text('Pequena'),
                                ),
                                ButtonSegment(
                                  value: 'medium',
                                  label: Text('Média'),
                                ),
                                ButtonSegment(
                                  value: 'large',
                                  label: Text('Grande'),
                                ),
                              ],
                              selected: {chatPrefs.chatFontSize},
                              onSelectionChanged: (selection) {
                                ref
                                    .read(chatPreferencesProvider.notifier)
                                    .setChatFontSize(selection.first);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.keyboard_return_rounded, color: accent),
                      title: const Text('Enter para enviar'),
                      subtitle: const Text(
                        'A tecla Enter do teclado envia a mensagem diretamente.',
                      ),
                      value: chatPrefs.enterToSend,
                      onChanged: (value) => ref
                          .read(chatPreferencesProvider.notifier)
                          .setEnterToSend(value),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.download_for_offline_rounded, color: accent),
                      title: const Text('Download automático de mídia'),
                      subtitle: Text(
                        _autoDownloadLabel(chatPrefs.autoDownloadMedia),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: () =>
                          _openAutoDownloadPicker(chatPrefs.autoDownloadMedia),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.archive_rounded, color: accent),
                      title: const Text('Conversas arquivadas'),
                      subtitle: Text(
                        archivedCount == 0
                            ? 'Nenhuma conversa arquivada'
                            : '$archivedCount arquivada(s)',
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: _openArchivedChatsSheet,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. NOTIFICAÇÕES
              _SectionTitle(label: 'Notificações', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _notificationsEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: _notificationsEnabled
                            ? accent
                            : Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Permissão no celular'),
                      subtitle: Text(
                        _notificationsEnabled
                            ? 'Ativadas para novas mensagens'
                            : 'Desativadas — toque para ativar',
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: _handleNotificationsTap,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.visibility_off_rounded, color: accent),
                      title: const Text('Ocultar conteúdo nas notificações'),
                      subtitle: const Text(
                        'Exibe apenas o nome de quem enviou na tela bloqueada.',
                      ),
                      value: chatPrefs.notifHidePreview,
                      onChanged: (value) => ref
                          .read(chatPreferencesProvider.notifier)
                          .setNotificationHidePreview(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.volume_up_rounded, color: accent),
                      title: const Text('Som nas notificações'),
                      subtitle: const Text(
                        'Tocar som ao receber novas mensagens',
                      ),
                      value: chatPrefs.notifSoundEnabled,
                      onChanged: (value) => ref
                          .read(chatPreferencesProvider.notifier)
                          .setNotificationSound(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(Icons.vibration_rounded, color: accent),
                      title: const Text('Vibração'),
                      subtitle: const Text(
                        'Vibrar ao receber novas mensagens',
                      ),
                      value: chatPrefs.notifVibrationEnabled,
                      onChanged: (value) => ref
                          .read(chatPreferencesProvider.notifier)
                          .setNotificationVibration(value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(
                        Icons.mark_chat_unread_rounded,
                        color: accent,
                      ),
                      title: const Text('Alertas com o app fechado'),
                      subtitle: const Text(
                        'Mantém o aviso de novas mensagens sempre ativo.',
                      ),
                      value: _backgroundModeEnabled,
                      onChanged: _toggleBackgroundMode,
                    ),
                    if (!_ignoringBattery) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.battery_saver_rounded,
                          color: accent,
                        ),
                        title: const Text('Receber avisos com a tela apagada'),
                        subtitle: const Text(
                          'Evita atrasos quando o celular economiza energia.',
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: secondaryText,
                        ),
                        onTap: _requestBatteryExemption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 5. ARMAZENAMENTO
              _SectionTitle(label: 'Armazenamento', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.storage_rounded, color: accent),
                      title: const Text('Cache de mídia local'),
                      subtitle: Text(_formatCacheSize(_cacheBytes)),
                      trailing: _isClearingCache
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: (_cacheBytes ?? 0) > 0
                                  ? _confirmClearCache
                                  : null,
                              child: const Text('Limpar cache'),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 6. APARÊNCIA
              _SectionTitle(label: 'Aparência', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.palette_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Tema',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ThemeMode>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  icon: Icon(Icons.brightness_auto_rounded,
                                      size: 18),
                                  label: Text('Sistema'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  icon: Icon(Icons.light_mode_rounded, size: 18),
                                  label: Text('Claro'),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  icon: Icon(Icons.dark_mode_rounded, size: 18),
                                  label: Text('Escuro'),
                                ),
                              ],
                              selected: {themeMode},
                              onSelectionChanged: (selection) {
                                ref
                                    .read(appearanceProvider.notifier)
                                    .setThemeMode(selection.first);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.color_lens_rounded,
                                size: 20,
                                color: accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Cor de destaque (${selectedAccent.label})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: AccentPreset.values.map((preset) {
                              final isSelected = preset.id == selectedAccent.id;
                              final swatchColor = isDark
                                  ? preset.primaryDark
                                  : preset.primaryLight;
                              return InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => ref
                                    .read(appearanceProvider.notifier)
                                    .setAccent(preset),
                                child: Tooltip(
                                  message: preset.label,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: swatchColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Colors.transparent,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            size: 20,
                                            color: isDark
                                                ? preset.onPrimaryDark
                                                : Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 7. SOBRE
              _SectionTitle(label: 'Sobre', color: secondaryText),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.info_outline_rounded, color: accent),
                      title: const Text('Versão instalada'),
                      subtitle: Text('Zapi $versionLabel'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: !_isCheckingUpdate,
                      leading: Icon(Icons.system_update_rounded, color: accent),
                      title: const Text('Verificar atualizações'),
                      trailing: _isCheckingUpdate
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              color: secondaryText,
                            ),
                      onTap: _checkForUpdatesManually,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.auto_awesome_rounded, color: accent),
                      title: const Text('O que há de novo'),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: secondaryText,
                      ),
                      onTap: () => _showWhatsNewSheet(versionLabel),
                    ),
                  ],
                ),
              ),
              if (isAuthBusy) ...[
                const SizedBox(height: 18),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onForgotPassword});

  final Future<void> Function() onForgotPassword;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _nextController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _nextController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(
        context,
        (current: _currentController.text, next: _nextController.text),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Alterar senha'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Senha atual',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Informe sua senha atual.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nextController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
                validator: Validators.validatePassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirmar nova senha',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Confirme a nova senha.';
                  }
                  if (value != _nextController.text) {
                    return 'As senhas não coincidem.';
                  }
                  return null;
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onForgotPassword();
                  },
                  child: const Text('Esqueci minha senha'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Salvar nova senha'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excluir conta permanentemente'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Todos os seus dados (perfil, @usuário, ID e foto) serão apagados definitivamente. Digite sua senha atual para confirmar:',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Senha atual',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Informe sua senha atual.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('Excluir conta'),
        ),
      ],
    );
  }
}
