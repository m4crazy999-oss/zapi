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
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/profile_banner.dart';
import '../../../../core/widgets/profile_header_actions.dart';
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
  bool _isUploadingBanner = false;
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
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _idSyncError = e.message);
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      const msg = 'Não foi possível gerar o ID agora. Tente novamente.';
      setState(() => _idSyncError = msg);
      ZapiToast.showError(context, msg);
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

      await ref
          .read(profileControllerProvider.notifier)
          .uploadPhoto(compressedBytes);
      if (!mounted) return;
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível atualizar a foto de perfil.',
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
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  Future<void> _handlePickBanner() async {
    try {
      setState(() => _isUploadingBanner = true);
      final compressedBytes = await ImageHelper.pickCropAndCompressBanner(context);
      if (compressedBytes == null) {
        if (mounted) setState(() => _isUploadingBanner = false);
        return;
      }

      await ref
          .read(profileControllerProvider.notifier)
          .uploadBanner(compressedBytes);
      if (!mounted) return;
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível atualizar o banner agora.',
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingBanner = false);
      }
    }
  }

  Future<void> _handleRemoveBanner() async {
    try {
      setState(() => _isUploadingBanner = true);
      await ref.read(profileControllerProvider.notifier).removeBanner();
      if (!mounted) return;
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } finally {
      if (mounted) {
        setState(() => _isUploadingBanner = false);
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
                    Icons.delete_rounded,
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

  void _showBannerOptions(AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Escolher imagem ou GIF da galeria'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _handlePickBanner();
                },
              ),
              if (user.hasBanner)
                ListTile(
                  leading: Icon(
                    Icons.delete_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remover banner atual',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _handleRemoveBanner();
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
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível salvar seu perfil agora.',
      );
    }
  }

  void _showQrCodeDialog(AppUser user) {
    final codeValue =
        user.publicId.isNotEmpty ? user.publicId : '@${user.username}';
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final accent = isDark ? AppColors.emeraldBright : AppColors.emeraldDark;
        return AlertDialog(
          title: const Text('Meu QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.25),
                  ),
                ),
                child: CustomPaint(
                  size: const Size(184, 184),
                  painter: _ZapiQrPainter(seedText: codeValue),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                user.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(dialogCtx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (user.username.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '@${user.username}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (user.publicId.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText(
                  user.publicId,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                _copyIdentifier(codeValue, 'ID');
                ZapiToast.showInfo(dialogCtx, 'Código copiado.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profileMutation = ref.watch(profileControllerProvider);
    final isSaving = profileMutation.isLoading &&
        !_isUploadingPhoto &&
        !_isUploadingBanner &&
        !_isSyncingId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final currentUser = profileAsync.value;
    final hasCustomBanner = currentUser?.hasBanner ?? false;
    final topPadding = MediaQuery.paddingOf(context).top;

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
              onDarkBackdrop: hasCustomBanner || isDark,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        actions: [
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ProfileHeaderActionPill(
                  icon: Icons.wallpaper_rounded,
                  label: _isUploadingBanner ? 'Enviando...' : 'Alterar banner',
                  onDarkBackdrop: hasCustomBanner || isDark,
                  onPressed: _isUploadingBanner
                      ? null
                      : () => _showBannerOptions(currentUser),
                ),
              ),
            ),
        ],
      ),
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
                        'Seu perfil ainda está sendo preparado.',
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

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 44),
                      child: ProfileBanner(
                        bannerBase64: user.bannerBase64,
                        height: 176 + topPadding,
                      ),
                    ),
                    ZapiAvatar(
                      displayName: user.displayName,
                      photoBase64: user.photoBase64,
                      photoUrl: user.photoUrl,
                      radius: 52,
                      showEditBadge: true,
                      isLoading: _isUploadingPhoto,
                      onTap: () => _showPhotoOptions(user),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (user.hideLastSeen
                              ? secondaryText
                              : AppColors.emerald)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: user.hideLastSeen
                                ? secondaryText
                                : AppColors.emerald,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          user.hideLastSeen
                              ? 'Visto por último oculto'
                              : 'Online agora',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: user.hideLastSeen
                                ? secondaryText
                                : (isDark
                                    ? AppColors.emeraldBright
                                    : AppColors.emeraldDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                        Expanded(
                                          child: Text(
                                            'Seu ID exclusivo e @usuário',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: secondaryText,
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          onPressed: () =>
                                              _showQrCodeDialog(user),
                                          icon: const Icon(
                                            Icons.qr_code_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('QR Code'),
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
                                            'Seu código ZP-... ainda não foi gerado. Enquanto isso, outras pessoas podem adicionar você usando @${user.username}.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: _idSyncError != null
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
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
                                                      Icons
                                                          .auto_fix_high_rounded,
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
                            const SizedBox(height: 18),
                            ZapiTextField(
                              controller: _nameController,
                              label: 'Nome de exibição',
                              prefixIcon: Icons.person_rounded,
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
                              onChanged: (val) =>
                                  _checkUsername(val, user.username),
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
                                    ] else if (_usernameAvailable ==
                                        false) ...[
                                      Icon(
                                        Icons.cancel_rounded,
                                        size: 16,
                                        color:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Este @usuário já está em uso.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
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
                              prefixIcon: Icons.format_quote_rounded,
                              enabled: !isSaving,
                              maxLength: AppConstants.maxAboutLength,
                              maxLines: 2,
                              validator: Validators.validateAbout,
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: (isSaving ||
                                      _isUploadingPhoto ||
                                      _isUploadingBanner)
                                  ? null
                                  : _saveProfile,
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
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ZapiQrPainter extends CustomPainter {
  const _ZapiQrPainter({required this.seedText});

  final String seedText;

  static const int _gridSize = 21;

  bool _inFinder(int r, int c) {
    final topLeft = r < 7 && c < 7;
    final topRight = r < 7 && c >= _gridSize - 7;
    final bottomLeft = r >= _gridSize - 7 && c < 7;
    return topLeft || topRight || bottomLeft;
  }

  bool _finderModule(int lr, int lc) {
    if (lr == 0 || lr == 6 || lc == 0 || lc == 6) return true;
    if (lr == 1 || lr == 5 || lc == 1 || lc == 5) return false;
    return lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final module = size.width / _gridSize;
    final paint = Paint()..color = const Color(0xFF111B21);

    var hash = 0x811C9DC5;
    for (final unit in seedText.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }

    for (var r = 0; r < _gridSize; r++) {
      for (var c = 0; c < _gridSize; c++) {
        bool filled;
        if (_inFinder(r, c)) {
          final lr = r >= _gridSize - 7 ? r - (_gridSize - 7) : r;
          final lc = c >= _gridSize - 7 ? c - (_gridSize - 7) : c;
          filled = _finderModule(lr, lc);
        } else if ((r == 7 && (c < 8 || c >= _gridSize - 8)) ||
            (c == 7 && (r < 8 || r >= _gridSize - 8)) ||
            (r == _gridSize - 8 && c < 8)) {
          filled = false;
        } else if (r == 6 || c == 6) {
          filled = (r + c).isEven;
        } else {
          final bitSeed = (hash ^ (r * 73856093) ^ (c * 19349663)) & 0x7FFFFFFF;
          filled = ((bitSeed >> 3) & 1) == 1;
        }
        if (filled) {
          canvas.drawRect(
            Rect.fromLTWH(c * module, r * module, module + 0.3, module + 0.3),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZapiQrPainter oldDelegate) =>
      oldDelegate.seedText != seedText;
}
