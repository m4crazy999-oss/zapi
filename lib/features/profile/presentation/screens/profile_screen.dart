import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../../core/utils/validators.dart';
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
      final compressedBytes = await ImageHelper.pickCropAndCompressAvatar(source);
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
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto com a câmera'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handlePhotoSource(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Escolher da galeria'),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profileMutation = ref.watch(profileControllerProvider);
    final isSaving = profileMutation.isLoading && !_isUploadingPhoto;
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
            child: Text(
              'Não foi possível carregar seu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText),
            ),
          ),
        ),
        data: (user) {
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _syncInitialValues(user);

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
                        Center(
                          child: ZapiAvatar(
                            displayName: user.displayName,
                            photoBase64: user.photoBase64,
                            photoUrl: user.photoUrl,
                            radius: 56,
                            showEditBadge: true,
                            isLoading: _isUploadingPhoto,
                            onTap: () => _showPhotoOptions(user),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Toque na foto para alterar (máx. 256×256 · até 100 KB)',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: secondaryText),
                        ),
                        const SizedBox(height: 28),
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
                            leading: const Icon(Icons.email_outlined),
                            title: const Text('E-mail da conta'),
                            subtitle: Text(user.email),
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
