import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/profile_banner.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_text_field.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/profile_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _aboutController = TextEditingController();

  bool _initialized = false;
  bool _isUploadingPhoto = false;
  bool _isSyncingId = false;
  String? _idSyncError;
  bool? _usernameAvailable;
  bool _checkingUsername = false;
  String _lastCheckedUsername = '';

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _syncInitialValues(AppUser user) {
    if (_initialized) return;
    _nameController.text = user.displayName;
    _usernameController.text = user.username;
    _aboutController.text = user.about;
    _initialized = true;
  }

  Future<void> _syncOrGenerateId() async {
    if (_isSyncingId) return;
    setState(() {
      _isSyncingId = true;
      _idSyncError = null;
    });
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .syncAccountAndGenerateId();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil e ID exclusivo sincronizados!')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _idSyncError = e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      const msg = 'Não foi possível gerar o ID agora. Tente novamente.';
      setState(() => _idSyncError = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingId = false);
      }
    }
  }

  Future<void> _checkUsername(String value, String currentUsername) async {
    final normalized = Validators.normalizeUsername(value);
    if (normalized == currentUsername ||
        Validators.validateUsername(normalized) != null) {
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

  Future<void> _handlePhotoSource(ImageSource source) async {
    try {
      setState(() => _isUploadingPhoto = true);
      final compressedBytes =
          await ImageHelper.pickCropAndCompressAvatar(context, source);
      if (compressedBytes == null) {
        if (mounted) setState(() => _isUploadingPhoto = false);
        return;
      }

      await ref.read(profileControllerProvider.notifier).uploadPhoto(compressedBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada!')),
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
          content: const Text('Não foi possível atualizar a foto de perfil.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _handleRemovePhoto() async {
    try {
      setState(() => _isUploadingPhoto = true);
      await ref.read(profileControllerProvider.notifier).removePhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil removida.')),
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
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  void _showPhotoOptions(AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Tirar foto com a câmera'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handlePhotoSource(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Escolher foto ou GIF da galeria'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handlePhotoSource(ImageSource.gallery);
                },
              ),
              if (user.hasPhoto)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remover foto atual',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleRemovePhoto();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyIdentifier(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label $value copiado!')),
    );
  }

  Future<void> _shareIdentifiers(AppUser user) async {
    final lines = <String>['Me adicione no Zapi!'];
    if (user.publicId.isNotEmpty) {
      lines.add('Meu ID: ${user.publicId}');
    }
    if (user.username.isNotEmpty) {
      lines.add('Meu @usuário: @${user.username}');
    }
    await Share.share(lines.join('\n'));
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      await ref.read(profileControllerProvider.notifier).updateProfile(
            displayName: _nameController.text,
            username: _usernameController.text,
            about: _aboutController.text,
          );
      if (!mounted) return;
      setState(() => _usernameAvailable = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado com sucesso!')),
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
          content: const Text('Não foi possível salvar seu perfil agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final privateEmail = ref.watch(privateAccountEmailProvider).value ??
        ref.watch(firebaseAuthProvider).currentUser?.email ??
        '';
    final profileMutation = ref.watch(profileControllerProvider);
    final isSaving =
        profileMutation.isLoading && !_isUploadingPhoto && !_isSyncingId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Não foi possível carregar seu perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isSyncingId ? null : _syncOrGenerateId,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
        data: (user) {
          if (user == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_search_rounded,
                        size: 56,
                        color: AppColors.emerald,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Seu perfil ainda não foi inicializado no servidor.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _idSyncError ??
                            'Toque abaixo para criar seus dados de perfil e gerar seu ID exclusivo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _idSyncError != null
                              ? Theme.of(context).colorScheme.error
                              : secondaryText,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _isSyncingId ? null : _syncOrGenerateId,
                        icon: _isSyncingId
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high_rounded),
                        label: Text(
                          _isSyncingId
                              ? 'Sincronizando...'
                              : 'Concluir perfil e gerar ID',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          _syncInitialValues(user);
          final hasPublicId = user.publicId.trim().isNotEmpty;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.bottomCenter,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 52),
                              child: ProfileBanner(
                                preset: user.bannerPreset,
                                height: 150,
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                shape: BoxShape.circle,
                              ),
                              child: ZapiAvatar(
                                displayName: user.displayName,
                                photoBase64: user.photoBase64,
                                photoUrl: user.photoUrl,
                                radius: 52,
                                showEditBadge: true,
                                isLoading: _isUploadingPhoto,
                                onTap: () => _showPhotoOptions(user),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque na foto para alterar (aceita foto animada GIF/WebP)',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondaryText),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Estilo do banner',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: secondaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: AppConstants.bannerPresets.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final preset = AppConstants.bannerPresets[index];
                              final selected = user.bannerPreset == preset.id;
                              final palette =
                                  ProfileBanner.paletteFor(preset.id);
                              return ChoiceChip(
                                selected: selected,
                                showCheckmark: false,
                                avatar: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        palette.colors.first,
                                        palette.colors.last,
                                      ],
                                    ),
                                  ),
                                ),
                                label: Text(preset.label),
                                onSelected: (_) async {
                                  try {
                                    await ref
                                        .read(
                                            profileControllerProvider.notifier)
                                        .updateBannerPreset(preset.id);
                                  } on AppException catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.message)),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 20,
                                      color: isDark
                                          ? AppColors.emeraldBright
                                          : AppColors.emeraldDark,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Seu ID exclusivo e @usuário',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (hasPublicId) ...[
                                  SelectableText(
                                    user.publicId,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '@${user.username}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.emeraldBright
                                          : AppColors.emeraldDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Compartilhe este ID ou seu @usuário para que outras pessoas adicionem você sem precisar do seu e-mail.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _copyIdentifier(
                                            user.publicId,
                                            'ID',
                                          ),
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Copiar ID'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _shareIdentifiers(user),
                                          icon: const Icon(
                                            Icons.share_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Compartilhar'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  SelectableText(
                                    '@${user.username}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _idSyncError ??
                                        'Seu código ZP-... ainda não foi gravado no servidor. Enquanto isso, outras pessoas podem adicionar você usando @${user.username}.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: _idSyncError != null
                                          ? Theme.of(context).colorScheme.error
                                          : secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _isSyncingId
                                              ? null
                                              : _syncOrGenerateId,
                                          icon: _isSyncingId
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.auto_fix_high_rounded,
                                                  size: 18,
                                                ),
                                          label: Text(
                                            _isSyncingId
                                                ? 'Gerando...'
                                                : 'Gerar meu ID',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _copyIdentifier(
                                            '@${user.username}',
                                            '@usuário',
                                          ),
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Copiar @'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ZapiTextField(
                          controller: _nameController,
                          label: 'Nome de exibição',
                          prefixIcon: Icons.person_outline_rounded,
                          enabled: !isSaving,
                          maxLength: AppConstants.maxDisplayNameLength,
                          validator: Validators.validateDisplayName,
                        ),
                        const SizedBox(height: 12),
                        ZapiTextField(
                          controller: _usernameController,
                          label: 'Nome de usuário',
                          prefixText: '@',
                          prefixIcon: Icons.alternate_email_rounded,
                          enabled: !isSaving,
                          onChanged: (val) => _checkUsername(val, user.username),
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Verificando @usuário...',
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
                        const SizedBox(height: 12),
                        ZapiTextField(
                          controller: _aboutController,
                          label: 'Recado',
                          hint: 'Escreva algo sobre você',
                          prefixIcon: Icons.info_outline_rounded,
                          enabled: !isSaving,
                          maxLength: AppConstants.maxAboutLength,
                          maxLines: 2,
                          validator: Validators.validateAbout,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.lock_outline_rounded),
                            title: const Text('E-mail privado da conta'),
                            subtitle: Text(
                              privateEmail.isNotEmpty
                                  ? '$privateEmail\nVisível apenas para você'
                                  : 'Visível apenas para você',
                            ),
                            isThreeLine: privateEmail.isNotEmpty,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed:
                              (isSaving || _isUploadingPhoto) ? null : _saveProfile,
                          child: isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Salvar alterações'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
