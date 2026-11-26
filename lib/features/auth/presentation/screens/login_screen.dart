import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/zapi_logo.dart';
import '../../../../core/widgets/zapi_text_field.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      const msg = 'Não foi possível entrar agora. Tente novamente.';
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: ZapiLogo(size: 80, showLabel: true)),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.appTagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: secondaryText,
                          ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'Entrar na sua conta',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    ZapiTextField(
                      controller: _emailController,
                      label: 'E-mail',
                      hint: 'seu@email.com',
                      prefixIcon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !_submitting,
                      validator: Validators.validateEmail,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 14),
                    ZapiTextField(
                      controller: _passwordController,
                      label: 'Senha',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      enabled: !_submitting,
                      validator: Validators.validatePassword,
                      onFieldSubmitted: (_) => _submit(),
                      autofillHints: const [AutofillHints.password],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.push('/forgot-password'),
                        child: const Text('Esqueci a senha'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Ainda não tem conta?',
                          style: TextStyle(color: secondaryText),
                        ),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => context.push('/register'),
                          child: const Text('Criar conta'),
                        ),
                      ],
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
