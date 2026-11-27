import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_exceptions.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/zapi_toast.dart';
import '../../../../core/widgets/zapi_camera_screen.dart';
import '../../../../core/widgets/zapi_photo_editor_screen.dart';
import '../../../../core/widgets/zapi_video_trimmer_screen.dart';
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

  String _mode = 'text'; // 'text' | 'image' | 'video'

  // Estilo do status de texto
  int _presetIndex = 0;
  int _textColorIndex = 0;
  int _fontIndex = 0;
  int _alignIndex = 0;
  int _sizeIndex = 1; // 0 = 20, 1 = 26, 2 = 32

  static const _fonts = [
    ('sans', 'Moderna'),
    ('serif', 'Clássica'),
    ('mono', 'Máquina'),
    ('display', 'Destaque'),
  ];
  static const _alignments = [
    ('center', TextAlign.center, Icons.format_align_center_rounded),
    ('left', TextAlign.left, Icons.format_align_left_rounded),
    ('right', TextAlign.right, Icons.format_align_right_rounded),
  ];
  static const _fontSizes = [20.0, 26.0, 32.0];

  // Mídia selecionada (Foto / Vídeo)
  String? _selectedPhotoPath;
  String? _selectedVideoPath;
  int _selectedVideoDurationMs = 0;
  VideoPlayerController? _videoController;

  bool _publishing = false;

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  StatusStylePreset get _activePreset => StatusItem.stylePresets[_presetIndex];

  TextStyle _buildTextStatusStyle({
    required String fontKey,
    required Color color,
    required double fontSize,
  }) {
    return switch (fontKey) {
      'serif' => TextStyle(
          fontFamily: 'serif',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      'mono' => TextStyle(
          fontFamily: 'monospace',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      'display' => TextStyle(
          color: color,
          fontSize: fontSize + 2,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.6,
          height: 1.28,
        ),
      _ => TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
    };
  }

  Future<void> _openPhotoFlow() async {
    final captured = await Navigator.push<ZapiCapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => const ZapiCameraScreen(
          allowVideo: false,
          maxPhotos: 1,
        ),
      ),
    );
    if (captured == null || captured.paths.isEmpty || !mounted) return;
    await _editPhotoForStatus(captured.paths.first);
  }

  Future<void> _editPhotoForStatus(String sourcePath) async {
    final edited = await Navigator.push<
        List<({String sourcePath, String caption})>>(
      context,
      MaterialPageRoute(
        builder: (_) => ZapiPhotoEditorScreen(
          initialPaths: [sourcePath],
          sendButtonLabel: 'Usar no status',
          captionHint: 'Adicione uma legenda...',
        ),
      ),
    );
    if (edited == null || edited.isEmpty || !mounted) return;

    setState(() {
      _mode = 'image';
      _selectedPhotoPath = edited.first.sourcePath;
      if (edited.first.caption.trim().isNotEmpty) {
        _captionController.text = edited.first.caption.trim();
      }
    });
  }

  Future<void> _openVideoFlow() async {
    final captured = await Navigator.push<ZapiCapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => const ZapiCameraScreen(
          allowVideo: true,
          maxPhotos: 1,
        ),
      ),
    );
    if (captured == null || captured.paths.isEmpty || !mounted) return;

    if (captured.kind == ZapiCapturedMediaKind.photos) {
      await _editPhotoForStatus(captured.paths.first);
      return;
    }

    final trimmed = await Navigator.push<TrimmedVideoOutput>(
      context,
      MaterialPageRoute(
        builder: (_) => ZapiVideoTrimmerScreen(
          videoPath: captured.paths.first,
          maxBytes: AppConstants.maxStatusVideoBytes,
          maxDurationMs: 60000,
          captionHint: 'Adicione uma legenda...',
          primaryButtonLabel: 'Usar no status',
        ),
      ),
    );
    if (trimmed == null || !mounted) return;

    await _setPreviewVideo(trimmed.path, trimmed.durationMs, trimmed.caption);
  }

  Future<void> _setPreviewVideo(
    String path,
    int durationMs,
    String caption,
  ) async {
    final prev = _videoController;
    _videoController = null;
    await prev?.dispose();

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _mode = 'video';
        _selectedVideoPath = path;
        _selectedVideoDurationMs = durationMs;
        _videoController = controller;
        if (caption.trim().isNotEmpty) {
          _captionController.text = caption.trim();
        }
      });
      await controller.play();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível carregar este vídeo.');
    }
  }

  String _privacyLabel(
    StatusPrivacyMode mode,
    int favoriteCount,
    int customCount,
  ) {
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
      ZapiToast.showError(
        context,
        'Aguarde carregar seu perfil antes de publicar.',
      );
      return;
    }

    final contacts = ref.read(contactsListProvider).value ?? const [];
    final prefs = ref.read(chatPreferencesProvider);
    final privacyMode = StatusPrivacyMode.fromCode(prefs.statusPrivacyMode);

    setState(() => _publishing = true);
    try {
      final repo = ref.read(statusRepositoryProvider);
      if (_mode == 'image') {
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
      } else if (_mode == 'video') {
        final videoPath = _selectedVideoPath;
        if (videoPath == null) {
          throw const AppException('Escolha um vídeo para publicar no Status.');
        }
        await repo.createVideoStatus(
          owner: user,
          sourceVideoPath: videoPath,
          durationMs: _selectedVideoDurationMs,
          caption: _captionController.text,
          contacts: contacts,
          privacyMode: privacyMode,
          customUids: prefs.statusCustomUids,
        );
      } else {
        final preset = _activePreset;
        final textColor = StatusItem.textColorOptions[_textColorIndex];
        await repo.createTextStatus(
          owner: user,
          text: _textController.text,
          backgroundColor: preset.backgroundColor,
          backgroundGradientEnd: preset.backgroundGradientEnd,
          textColor: textColor,
          fontStyle: _fonts[_fontIndex].$1,
          textAlign: _alignments[_alignIndex].$1,
          fontSize: _fontSizes[_sizeIndex],
          contacts: contacts,
          privacyMode: privacyMode,
          customUids: prefs.statusCustomUids,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } on AppException catch (e) {
      if (!mounted) return;
      ZapiToast.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(
        context,
        'Não foi possível publicar este status agora.',
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

    final preset = _activePreset;
    final bgStart = Color(preset.backgroundColor);
    final bgEnd = preset.backgroundGradientEnd != null
        ? Color(preset.backgroundGradientEnd!)
        : null;
    final isLightPreset =
        _mode == 'text' && bgStart.computeLuminance() > 0.62;
    final chromeForeground = isLightPreset ? AppColors.lightTextPrimary : Colors.white;
    final textColor = Color(StatusItem.textColorOptions[_textColorIndex]);

    return Scaffold(
      backgroundColor: _mode == 'text' ? bgStart : AppColors.darkBackground,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: _mode == 'text'
            ? BoxDecoration(
                color: bgEnd == null ? bgStart : null,
                gradient: bgEnd != null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [bgStart, bgEnd],
                      )
                    : null,
              )
            : const BoxDecoration(color: AppColors.darkBackground),
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: _publishing ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: chromeForeground),
                    ),
                    Expanded(
                      child: Center(
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.28),
                            selectedBackgroundColor: AppColors.emerald,
                            selectedForegroundColor: Colors.white,
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment<String>(
                              value: 'text',
                              icon: Icon(Icons.title_rounded, size: 16),
                              label: Text('Texto'),
                            ),
                            ButtonSegment<String>(
                              value: 'image',
                              icon: Icon(Icons.photo_rounded, size: 16),
                              label: Text('Foto'),
                            ),
                            ButtonSegment<String>(
                              value: 'video',
                              icon: Icon(Icons.videocam_rounded, size: 16),
                              label: Text('Vídeo'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: _publishing
                              ? null
                              : (next) {
                                  final selectedMode = next.first;
                                  setState(() => _mode = selectedMode);
                                  if (selectedMode == 'image' &&
                                      _selectedPhotoPath == null) {
                                    _openPhotoFlow();
                                  } else if (selectedMode == 'video' &&
                                      _selectedVideoPath == null) {
                                    _openVideoFlow();
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),

              // Barra rápida de tipografia no modo Texto
              if (_mode == 'text')
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _StatusToolPill(
                          icon: Icons.text_fields_rounded,
                          label: _fonts[_fontIndex].$2,
                          onTap: () => setState(() {
                            _fontIndex = (_fontIndex + 1) % _fonts.length;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _StatusToolPill(
                          icon: _alignments[_alignIndex].$3,
                          label: 'Alinhar',
                          onTap: () => setState(() {
                            _alignIndex =
                                (_alignIndex + 1) % _alignments.length;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _StatusToolPill(
                          icon: Icons.format_size_rounded,
                          label: '${_fontSizes[_sizeIndex].round()}',
                          onTap: () => setState(() {
                            _sizeIndex = (_sizeIndex + 1) % _fontSizes.length;
                          }),
                        ),
                        const SizedBox(width: 8),
                        _StatusToolPill(
                          icon: Icons.format_color_text_rounded,
                          label: 'Cor',
                          swatchColor: textColor,
                          onTap: () => setState(() {
                            _textColorIndex = (_textColorIndex + 1) %
                                StatusItem.textColorOptions.length;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),

              // Área principal
              Expanded(
                child: _buildMainContent(textColor, isLightPreset),
              ),

              // Seletor de fundos e degradês (modo Texto)
              if (_mode == 'text')
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: StatusItem.stylePresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, idx) {
                      final p = StatusItem.stylePresets[idx];
                      final selected = idx == _presetIndex;
                      final c1 = Color(p.backgroundColor);
                      final c2 = p.backgroundGradientEnd != null
                          ? Color(p.backgroundGradientEnd!)
                          : c1;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _presetIndex = idx;
                            final defaultIdx = StatusItem.textColorOptions
                                .indexOf(p.defaultTextColor);
                            if (defaultIdx >= 0) {
                              _textColorIndex = defaultIdx;
                            }
                          });
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [c1, c2],
                            ),
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.45),
                              width: selected ? 3 : 1.5,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Rodapé: legenda (se foto/vídeo), privacidade e botão enviar
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                color: Colors.black.withValues(alpha: 0.3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((_mode == 'image' && _selectedPhotoPath != null) ||
                        (_mode == 'video' && _selectedVideoPath != null)) ...[
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
                          fillColor: AppColors.darkSurfaceAlt,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
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
                                      builder: (_) =>
                                          const StatusPrivacyScreen(),
                                    ),
                                  );
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
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
                          width: 50,
                          height: 50,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(Color textColor, bool isLightPreset) {
    if (_mode == 'image') {
      if (_selectedPhotoPath == null) {
        return Center(
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
                  'Capture ou escolha uma foto para seu status',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _openPhotoFlow,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Câmera e galeria'),
                ),
              ],
            ),
          ),
        );
      }

      return Stack(
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _publishing
                      ? null
                      : () => _editPhotoForStatus(_selectedPhotoPath!),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 17),
                  label: const Text('Editar'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _publishing ? null : _openPhotoFlow,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: const Text('Trocar'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_mode == 'video') {
      final vc = _videoController;
      if (_selectedVideoPath == null || vc == null || !vc.value.isInitialized) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.video_call_rounded,
                  size: 60,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Grave ou escolha um vídeo de até 1 minuto',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _openVideoFlow,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.videocam_rounded),
                  label: const Text('Gravar ou escolher vídeo'),
                ),
              ],
            ),
          ),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () {
              if (vc.value.isPlaying) {
                vc.pause();
              } else {
                vc.play();
              }
              setState(() {});
            },
            child: Center(
              child: AspectRatio(
                aspectRatio:
                    vc.value.aspectRatio > 0 ? vc.value.aspectRatio : 9 / 16,
                child: VideoPlayer(vc),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                DateFormatter.formatDuration(
                  Duration(milliseconds: _selectedVideoDurationMs),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 14,
            child: FilledButton.tonalIcon(
              onPressed: _publishing ? null : _openVideoFlow,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.6),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: 17),
              label: const Text('Trocar vídeo'),
            ),
          ),
        ],
      );
    }

    // Modo Texto sem nenhuma borda ao redor do campo
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: const InputDecorationTheme(
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          child: TextField(
            controller: _textController,
            enabled: !_publishing,
            maxLength: AppConstants.maxStatusTextLength,
            maxLines: 9,
            minLines: 1,
            textAlign: _alignments[_alignIndex].$2,
            textCapitalization: TextCapitalization.sentences,
            style: _buildTextStatusStyle(
              fontKey: _fonts[_fontIndex].$1,
              color: textColor,
              fontSize: _fontSizes[_sizeIndex],
            ),
            cursorColor: textColor,
            decoration: InputDecoration(
              counterText: '',
              filled: false,
              fillColor: Colors.transparent,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'Digite um status...',
              hintStyle: _buildTextStatusStyle(
                fontKey: _fonts[_fontIndex].$1,
                color: isLightPreset
                    ? AppColors.lightTextPrimary.withValues(alpha: 0.45)
                    : textColor.withValues(alpha: 0.55),
                fontSize: _fontSizes[_sizeIndex],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusToolPill extends StatelessWidget {
  const _StatusToolPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.swatchColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? swatchColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatchColor != null)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: swatchColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 1.2),
                ),
              )
            else
              Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
