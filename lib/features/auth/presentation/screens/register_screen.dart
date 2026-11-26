import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/zapi_text_field.dart';
import '../providers/auth_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool? _usernameAvailable;
  bool _checkingUsername = false;
  String _lastCheckedUsername = '';

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkUsernameAvailability(String value) async {
    final normalized = Validators.normalizeUsername(value);
    if (Validators.validateUsername(normalized) != null) {
      if (mounted) {
        setState(() {
          _usernameAvailable = null;
          _checkingUsername = false;
          _lastCheckedUsername = normalized;
        });
      }
      return;
    }

    setState(() {
      _checkingUsername = true;
      _lastCheckedUsername = normalized;
    });

    try {
      final available = await ref
          .read(authRepositoryProvider)
          .isUsernameAvailable(normalized);
      if (mounted && _lastCheckedUsername == normalized) {
        setState(() {
          _usernameAvailable = available;
          _checkingUsername = false;
        });
      }
    } catch (_) {
      if (mounted && _lastCheckedUsername == normalized) {
        setState(() {
          _usernameAvailable = null;
          _checkingUsername = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      await ref.read(authControllerProvider.notifier).register(
            displayName: _displayNameController.text,
            username: _usernameController.text,
            email: _emailController.text,
            password: _passwordController.text,
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

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar conta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Configure seu perfil inicial no Zapi.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                          ),
                    ),
                    const SizedBox(height: 20),
                    ZapiTextField(
                      controller: _displayNameController,
                      label: 'Nome de exibição',
                      hint: 'Como seus contatos vão ver você',
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      validator: Validators.validateDisplayName,
                    ),
                    const SizedBox(height: 14),
                    ZapiTextField(
                      controller: _usernameController,
                      label: 'Nome de usuário',
                      hint: 'ex: rafael.silva',
                      prefixText: '@',
                      prefixIcon: Icons.alternate_email_rounded,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      onChanged: _checkUsernameAvailability,
                      validator: Validators.validateUsername,
                    ),
                    if (_checkingUsername || _usernameAvailable != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Row(
                          children: [
                            if (_checkingUsername) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Verificando disponibilidade...',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: secondaryText),
                              ),
                            ] else if (_usernameAvailable == true) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '@usuário disponível!',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else if (_usernameAvailable == false) ...[
                              Icon(
                                Icons.cancel_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Este @usuário já está em uso.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    ZapiTextField(
                      controller: _emailController,
                      label: 'E-mail',
                      hint: 'seu@email.com',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      validator: Validators.validateEmail,
                    ),
                    const SizedBox(height: 14),
                    ZapiTextField(
                      controller: _passwordController,
                      label: 'Senha',
                      hint: 'Mínimo de 6 caracteres',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      validator: Validators.validatePassword,
                    ),
                    const SizedBox(height: 14),
                    ZapiTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirmar senha',
                      prefixIcon: Icons.lock_reset_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      enabled: !isLoading,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        if ((value ?? '').isEmpty) {
                          return 'Confirme sua senha.';
                        }
                        if (value != _passwordController.text) {
                          return 'As senhas não coincidem.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Criar conta'),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: isLoading ? null : () => context.pop(),
                      child: const Text('Já tenho conta. Voltar para o login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
