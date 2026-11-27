import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/permission_helper.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/status_item.dart';
import '../providers/status_providers.dart';
import 'status_privacy_screen.dart';

class CreateStatusScreen extends ConsumerStatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  ConsumerState<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends ConsumerState<CreateStatusScreen> {
  final _textController = TextEditingController();
  final _captionController = TextEditingController();
  final _picker = ImagePicker();

  bool _isPhotoMode = false;
  int _colorIndex = 0;
  String? _selectedPhotoPath;
  bool _publishing = false;

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final allowed = source == ImageSource.camera
        ? await PermissionHelper.requestCamera(context)
        : await PermissionHelper.requestGallery(context);
    if (!allowed || !mounted) return;

    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;
      setState(() {
        _isPhotoMode = true;
        _selectedPhotoPath = picked.path;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esta foto.')),
      );
    }
  }

  String _privacyLabel(StatusPrivacyMode mode, int favoriteCount, int customCount) {
    return switch (mode) {
      StatusPrivacyMode.all => 'Todos os contatos',
      StatusPrivacyMode.favorites => 'Favoritos ($favoriteCount)',
      StatusPrivacyMode.custom => 'Selecionados ($customCount)',
    };
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final user = ref.read(currentUserProfileProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde carregar seu perfil antes de publicar.'),
        ),
      );
      return;
    }

    final contacts = ref.read(contactsListProvider).value ?? const [];
    final prefs = ref.read(chatPreferencesProvider);
    final privacyMode = StatusPrivacyMode.fromCode(prefs.statusPrivacyMode);

    setState(() => _publishing = true);
    try {
      final repo = ref.read(statusRepositoryProvider);
      if (_isPhotoMode) {
        final photoPath = _selectedPhotoPath;
        if (photoPath == null) {
          throw const AppException('Escolha uma foto para publicar no Status.');
        }
        await repo.createPhotoStatus(
          owner: user,
          sourceImagePath: photoPath,
          caption: _captionController.text,
          contacts: contacts,
          privacyMode: privacyMode,
          customUids: prefs.statusCustomUids,
        );
      } else {
        await repo.createTextStatus(
          owner: user,
          text: _textController.text,
          backgroundColor: StatusItem.textBackgroundColors[_colorIndex],
          contacts: contacts,
          privacyMode: privacyMode,
          customUids: prefs.statusCustomUids,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status publicado por 24 horas!')),
      );
      Navigator.pop(context);
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
          content: const Text('Não foi possível publicar este status agora.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(chatPreferencesProvider);
    final contacts = ref.watch(contactsListProvider).value ?? const [];
    final privacyMode = StatusPrivacyMode.fromCode(prefs.statusPrivacyMode);
    final favoriteCount = contacts.where((c) => c.isFavorite).length;
    final bgColor = _isPhotoMode
        ? const Color(0xFF0B141A)
        : Color(StatusItem.textBackgroundColors[_colorIndex]);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.25),
            selectedBackgroundColor: Colors.white,
            selectedForegroundColor: const Color(0xFF111B21),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            visualDensity: VisualDensity.compact,
          ),
          segments: const [
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.title_rounded, size: 17),
              label: Text('Texto'),
            ),
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.photo_rounded, size: 17),
              label: Text('Foto'),
            ),
          ],
          selected: {_isPhotoMode},
          onSelectionChanged: _publishing
              ? null
              : (next) {
                  final wantPhoto = next.first;
                  setState(() => _isPhotoMode = wantPhoto);
                  if (wantPhoto && _selectedPhotoPath == null) {
                    _pickPhoto(ImageSource.gallery);
                  }
                },
        ),
        actions: [
          if (!_isPhotoMode)
            IconButton(
              tooltip: 'Mudar cor de fundo',
              onPressed: _publishing
                  ? null
                  : () {
                      setState(() {
                        _colorIndex = (_colorIndex + 1) %
                            StatusItem.textBackgroundColors.length;
                      });
                    },
              icon: const Icon(Icons.palette_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isPhotoMode
                ? (_selectedPhotoPath != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Image.file(
                              File(_selectedPhotoPath!),
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 14,
                            child: FilledButton.tonalIcon(
                              onPressed: _publishing
                                  ? null
                                  : () => _pickPhoto(ImageSource.gallery),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.55),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                              label: const Text('Trocar'),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_photo_alternate_rounded,
                                size: 60,
                                color: Colors.white54,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Escolha uma foto para seu status',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _pickPhoto(ImageSource.gallery),
                                    icon: const Icon(Icons.photo_library_rounded),
                                    label: const Text('Galeria'),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white54,
                                      ),
                                    ),
                                    onPressed: () =>
                                        _pickPhoto(ImageSource.camera),
                                    icon: const Icon(Icons.camera_alt_rounded),
                                    label: const Text('Câmera'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ))
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: TextField(
                        controller: _textController,
                        enabled: !_publishing,
                        maxLength: AppConstants.maxStatusTextLength,
                        maxLines: 8,
                        minLines: 1,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          hintText: 'Digite um status...',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              color: Colors.black.withValues(alpha: 0.3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isPhotoMode && _selectedPhotoPath != null) ...[
                    TextField(
                      controller: _captionController,
                      enabled: !_publishing,
                      maxLength: AppConstants.maxStatusTextLength,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Adicione uma legenda...',
                        hintStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: const Color(0xFF1F2C34),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _publishing
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const StatusPrivacyScreen(),
                                  ),
                                );
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _privacyLabel(
                                  privacyMode,
                                  favoriteCount,
                                  prefs.statusCustomUids.length,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: FilledButton(
                          onPressed: _publishing ? null : _publish,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          child: _publishing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 22),
                        ),
                      ),
                    ],
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
