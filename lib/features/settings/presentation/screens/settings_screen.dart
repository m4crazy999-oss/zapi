import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/app_update_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _checkingUpdates = false;
  bool _sendingReset = false;
  bool _notificationsEnabled = true;
  bool _backgroundModeEnabled = true;
  bool _ignoringBattery = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshNotificationStatus();
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
    }
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notificações ativadas neste aparelho!'),
        ),
      );
      return;
    }

    await openAppSettings();
  }

  Future<void> _toggleBackgroundMode(bool value) async {
    setState(() => _backgroundModeEnabled = value);
    await ref.read(notificationServiceProvider).setBackgroundModeEnabled(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Recebimento com o aplicativo fechado ativado.'
              : 'Recebimento com o aplicativo fechado desativado.',
        ),
      ),
    );
  }

  Future<void> _requestBatteryExemption() async {
    await ref
        .read(notificationServiceProvider)
        .requestIgnoreBatteryOptimizations();
  }

  Future<void> _copyPublicId(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label $value copiado!')),
    );
  }

  Future<void> _checkUpdatesManually() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      final service = ref.read(appUpdateServiceProvider);
      final update = await service.checkForUpdate(force: true);
      if (!mounted) return;

      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você está com a versão mais recente.'),
          ),
        );
        return;
      }

      await UpdateDialog.show(
        context,
        update: update,
        updateService: service,
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível verificar atualizações agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingUpdates = false);
      }
    }
  }

  Future<void> _openChangePasswordDialog() async {
    final result = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null) return;

    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: result.current,
            newPassword: result.next,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha alterada com sucesso!')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível alterar sua senha agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _sendResetLinkToMyEmail() async {
    if (_sendingReset) return;
    final email = ref.read(privateAccountEmailProvider).value?.trim() ??
        ref.read(firebaseAuthProvider).currentUser?.email?.trim() ??
        '';

    if (email.isEmpty) {
      if (mounted) {
        context.push('/forgot-password');
      }
      return;
    }

    setState(() => _sendingReset = true);
    try {
      await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Link de recuperação enviado para $email (confira também o Spam).',
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível enviar o link de recuperação.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingReset = false);
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível sair da conta agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não foi possível excluir sua conta agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final versionLabel =
        ref.watch(appVersionLabelProvider).value ?? '1.0.0';
    final themeMode = ref.watch(themeModeProvider);
    final isAuthBusy = ref.watch(authControllerProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Meu perfil e ID'),
                subtitle: const Text('Toque para abrir e sincronizar seu perfil'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/profile'),
              ),
            ),
            data: (user) {
              if (user == null) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('Concluir perfil e gerar ID'),
                    subtitle: const Text(
                      'Toque para criar seus dados de perfil e visualizar seu ID.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/profile'),
                  ),
                );
              }
              final hasPublicId = user.publicId.trim().isNotEmpty;
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/profile'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ZapiAvatar(
                              displayName: user.displayName,
                              photoBase64: user.photoBase64,
                              photoUrl: user.photoUrl,
                              radius: 30,
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
                                      color: isDark
                                          ? AppColors.emeraldBright
                                          : AppColors.emeraldDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.about,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              size: 18,
                              color: isDark
                                  ? AppColors.emeraldBright
                                  : AppColors.emeraldDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hasPublicId
                                    ? 'ID exclusivo: ${user.publicId}'
                                    : 'ID exclusivo pendente — toque para gerar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: hasPublicId ? null : secondaryText,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: hasPublicId
                                  ? () => _copyPublicId(user.publicId, 'ID')
                                  : () => context.push('/profile'),
                              icon: Icon(
                                hasPublicId
                                    ? Icons.copy_rounded
                                    : Icons.auto_fix_high_rounded,
                                size: 16,
                              ),
                              label: Text(hasPublicId ? 'Copiar' : 'Gerar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Privacidade e avisos',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.verified_user_outlined),
                  title: Text('E-mail privado'),
                  subtitle: Text(
                    'Seu e-mail é visível apenas para você. Outras pessoas encontram você pelo ID ou @usuário.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    _notificationsEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: _notificationsEnabled
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Notificações'),
                  subtitle: Text(
                    _notificationsEnabled
                        ? 'Ativadas. Você recebe alertas de novas mensagens.'
                        : 'Desativadas. Toque aqui para ativar nas configurações.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _handleNotificationsTap,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.mark_chat_unread_outlined),
                  title: const Text('Alertas com o app fechado'),
                  subtitle: const Text(
                    'Mantém o recebimento de mensagens ativo mesmo fora do aplicativo.',
                  ),
                  value: _backgroundModeEnabled,
                  onChanged: _toggleBackgroundMode,
                ),
                if (!_ignoringBattery) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.battery_saver_rounded),
                    title: const Text('Permitir sem restrição de bateria'),
                    subtitle: const Text(
                      'Evita que o celular pause seus avisos de mensagens com a tela desligada.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _requestBatteryExemption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Aparência',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tema do aplicativo',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          label: Text('Sistema'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('Claro'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('Escuro'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (selection) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(selection.first);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Sobre e atualizações',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('Verificar atualizações'),
              subtitle: Text('Versão $versionLabel'),
              trailing: _checkingUpdates
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingUpdates ? null : _checkUpdatesManually,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'Conta e segurança',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Editar perfil'),
                  subtitle: const Text('Nome, @usuário, ID exclusivo e foto'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/profile'),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !isAuthBusy,
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Alterar senha'),
                  subtitle: const Text('Defina uma nova senha informando a atual'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openChangePasswordDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !isAuthBusy && !_sendingReset,
                  leading: const Icon(Icons.mark_email_read_outlined),
                  title: const Text('Enviar e-mail de recuperação de senha'),
                  subtitle: const Text('Receba um link para redefinir sua senha'),
                  trailing: _sendingReset
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _sendResetLinkToMyEmail,
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
                    Icons.delete_forever_outlined,
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
          if (isAuthBusy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

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
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
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
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
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
