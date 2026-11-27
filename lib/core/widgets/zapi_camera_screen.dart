import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_colors.dart';
import '../utils/date_formatter.dart';
import '../utils/permission_helper.dart';
import '../utils/zapi_toast.dart';
import 'zapi_mascot.dart';

enum ZapiCapturedMediaKind {
  photos,
  video,
}

class ZapiCapturedMedia {
  const ZapiCapturedMedia({
    required this.kind,
    required this.paths,
  });

  final ZapiCapturedMediaKind kind;
  final List<String> paths;
}

class ZapiCameraScreen extends StatefulWidget {
  const ZapiCameraScreen({
    super.key,
    this.allowVideo = true,
    this.maxPhotos = 10,
    this.openGalleryOnStart = false,
  });

  final bool allowVideo;
  final int maxPhotos;
  final bool openGalleryOnStart;

  @override
  State<ZapiCameraScreen> createState() => _ZapiCameraScreenState();
}

class _ZapiCameraScreenState extends State<ZapiCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.auto;

  bool _initializingCamera = true;
  bool _cameraDenied = false;
  bool _takingPhoto = false;
  bool _isRecordingVideo = false;
  Duration _recordDuration = Duration.zero;
  Timer? _recordTimer;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  Offset? _focusPointNormalized;
  Timer? _focusHideTimer;

  bool _loadingGallery = true;
  bool _galleryDenied = false;
  List<AssetEntity> _recentAssets = const [];
  final Map<String, Uint8List> _thumbCache = {};
  final List<AssetEntity> _selectedAssets = [];
  bool _exportingSelection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _initCamera(),
      _loadRecentMedia(),
    ]);
    if (widget.openGalleryOnStart && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFullGallery();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isRecordingVideo) {
        unawaited(_stopVideoRecording(sendImmediately: false));
      }
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _focusHideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _initializingCamera = true;
      _cameraDenied = false;
    });

    final granted = await PermissionHelper.requestCameraForMedia(
      context,
      includeMicrophone: widget.allowVideo,
    );
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _initializingCamera = false;
        _cameraDenied = true;
      });
      return;
    }

    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializingCamera = false;
            _cameraDenied = true;
          });
        }
        return;
      }

      if (_cameraIndex >= _cameras.length) _cameraIndex = 0;
      await _setupController(_cameras[_cameraIndex]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializingCamera = false;
          _cameraDenied = true;
        });
      }
    }
  }

  Future<void> _setupController(CameraDescription description) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: widget.allowVideo,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = (await controller.getMaxZoomLevel()).clamp(_minZoom, 8.0);
        _currentZoom = _minZoom;
      } catch (_) {
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _currentZoom = 1.0;
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializingCamera = false;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _initializingCamera = false);
      }
    }
  }

  Future<void> _loadRecentMedia({bool askPermission = false}) async {
    if (!mounted) return;
    setState(() => _loadingGallery = true);

    try {
      if (askPermission) {
        final ok = await PermissionHelper.requestGallery(
          context,
          includeVideo: widget.allowVideo,
        );
        if (!ok) {
          if (mounted) {
            setState(() {
              _loadingGallery = false;
              _galleryDenied = true;
            });
          }
          return;
        }
      }

      final perm = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: widget.allowVideo ? RequestType.common : RequestType.image,
            mediaLocation: false,
          ),
        ),
      );
      if (!perm.hasAccess) {
        if (mounted) {
          setState(() {
            _loadingGallery = false;
            _galleryDenied = true;
          });
        }
        return;
      }

      final paths = await PhotoManager.getAssetPathList(
        type: widget.allowVideo ? RequestType.common : RequestType.image,
        hasAll: true,
      );

      final recent = paths.isNotEmpty
          ? await paths.first.getAssetListPaged(page: 0, size: 36)
          : <AssetEntity>[];

      if (!mounted) return;
      setState(() {
        _galleryDenied = false;
        _recentAssets = recent;
        _loadingGallery = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingGallery = false;
          _galleryDenied = true;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecordingVideo || _takingPhoto) return;
    setState(() {
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      _initializingCamera = true;
    });
    await _setupController(_cameras[_cameraIndex]);
  }

  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = switch (_flashMode) {
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.off,
      _ => FlashMode.auto,
    };
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {
      if (mounted) setState(() => _flashMode = FlashMode.off);
    }
  }

  IconData get _flashIcon => switch (_flashMode) {
        FlashMode.auto => Icons.flash_auto_rounded,
        FlashMode.always => Icons.flash_on_rounded,
        _ => Icons.flash_off_rounded,
      };

  Future<void> _handleTapToFocus(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final nx = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final ny =
        (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    final point = Offset(nx, ny);

    setState(() => _focusPointNormalized = point);
    _focusHideTimer?.cancel();
    _focusHideTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _focusPointNormalized = null);
    });

    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {}
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _takingPhoto ||
        _isRecordingVideo) {
      return;
    }

    setState(() => _takingPhoto = true);
    unawaited(HapticFeedback.mediumImpact());
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      Navigator.pop(
        context,
        ZapiCapturedMedia(
          kind: ZapiCapturedMediaKind.photos,
          paths: [shot.path],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ZapiToast.showError(context, 'Não foi possível tirar a foto agora.');
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!widget.allowVideo || _isRecordingVideo || _takingPhoto) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final micGranted = await Permission.microphone.isGranted;
    if (!micGranted && mounted) {
      await PermissionHelper.requestMicrophone(context);
    }

    try {
      try {
        await controller.prepareForVideoRecording();
      } catch (_) {}
      await controller.startVideoRecording();
      unawaited(HapticFeedback.heavyImpact());
      _recordDuration = Duration.zero;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted || !_isRecordingVideo) return;
        setState(() => _recordDuration += const Duration(seconds: 1));
        if (_recordDuration.inSeconds >= 60) {
          await _stopVideoRecording(sendImmediately: true);
        }
      });
      if (mounted) setState(() => _isRecordingVideo = true);
    } catch (_) {
      if (mounted) {
        ZapiToast.showError(context, 'Não foi possível gravar o vídeo.');
      }
    }
  }

  Future<void> _stopVideoRecording({required bool sendImmediately}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final controller = _controller;
    if (!_isRecordingVideo || controller == null) return;

    try {
      final video = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _isRecordingVideo = false);

      if (!sendImmediately) return;
      if (_recordDuration.inMilliseconds < 800) {
        ZapiToast.showInfo(
          context,
          'Segure o botão para gravar um vídeo ou toque para tirar foto.',
        );
        return;
      }

      Navigator.pop(
        context,
        ZapiCapturedMedia(
          kind: ZapiCapturedMediaKind.video,
          paths: [video.path],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isRecordingVideo = false);
    }
  }

  Future<void> _onAssetTap(AssetEntity asset) async {
    if (_exportingSelection) return;

    if (asset.type == AssetType.video) {
      if (!widget.allowVideo) {
        ZapiToast.showInfo(context, 'Escolha uma foto para esta tela.');
        return;
      }
      if (_selectedAssets.isNotEmpty) {
        ZapiToast.showInfo(context, 'Vídeos são enviados um de cada vez.');
        return;
      }
      await _returnSingleVideo(asset);
      return;
    }

    if (widget.maxPhotos <= 1) {
      setState(() => _exportingSelection = true);
      try {
        final file = await asset.file;
        if (!mounted || file == null) return;
        Navigator.pop(
          context,
          ZapiCapturedMedia(
            kind: ZapiCapturedMediaKind.photos,
            paths: [file.path],
          ),
        );
      } finally {
        if (mounted) setState(() => _exportingSelection = false);
      }
      return;
    }

    setState(() {
      final existingIdx = _selectedAssets.indexWhere((a) => a.id == asset.id);
      if (existingIdx >= 0) {
        _selectedAssets.removeAt(existingIdx);
      } else if (_selectedAssets.length < widget.maxPhotos) {
        _selectedAssets.add(asset);
      } else {
        ZapiToast.showInfo(
          context,
          'Você pode selecionar até ${widget.maxPhotos} fotos por vez.',
        );
      }
    });
  }

  Future<void> _returnSingleVideo(AssetEntity asset) async {
    setState(() => _exportingSelection = true);
    try {
      final file = await asset.file;
      if (!mounted) return;
      if (file == null || !await file.exists()) {
        ZapiToast.showError(context, 'Não foi possível abrir este vídeo.');
        return;
      }
      Navigator.pop(
        context,
        ZapiCapturedMedia(
          kind: ZapiCapturedMediaKind.video,
          paths: [file.path],
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingSelection = false);
    }
  }

  Future<void> _confirmMultiSelection() async {
    if (_selectedAssets.isEmpty || _exportingSelection) return;
    setState(() => _exportingSelection = true);
    try {
      final paths = <String>[];
      for (final asset in _selectedAssets) {
        final file = await asset.file;
        if (file != null && await file.exists()) {
          paths.add(file.path);
        }
      }
      if (!mounted || paths.isEmpty) return;
      Navigator.pop(
        context,
        ZapiCapturedMedia(
          kind: ZapiCapturedMediaKind.photos,
          paths: paths,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingSelection = false);
    }
  }

  Future<void> _openFullGallery() async {
    if (_galleryDenied) {
      await _loadRecentMedia(askPermission: true);
      if (_galleryDenied || !mounted) return;
    }

    final result = await showModalBottomSheet<ZapiCapturedMedia>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBackground,
      builder: (_) => _FullGallerySheet(
        allowVideo: widget.allowVideo,
        maxPhotos: widget.maxPhotos,
        initialSelectedIds: _selectedAssets.map((e) => e.id).toList(),
      ),
    );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  Future<Uint8List?> _getThumb(AssetEntity asset) async {
    final cached = _thumbCache[asset.id];
    if (cached != null) return cached;
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(180),
      quality: 80,
    );
    if (data != null && data.isNotEmpty) {
      if (_thumbCache.length > 120) _thumbCache.clear();
      _thumbCache[asset.id] = data;
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final cameraReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Preview da câmera em tela cheia
          if (cameraReady)
            LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _handleTapToFocus(d, constraints),
                  onScaleStart: (_) => _baseZoom = _currentZoom,
                  onScaleUpdate: (details) async {
                    if (_maxZoom <= _minZoom) return;
                    final next = (_baseZoom * details.scale)
                        .clamp(_minZoom, _maxZoom);
                    if ((next - _currentZoom).abs() < 0.03) return;
                    _currentZoom = next;
                    try {
                      await controller.setZoomLevel(next);
                    } catch (_) {}
                    if (mounted) setState(() {});
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: 1 / controller.value.aspectRatio,
                          child: CameraPreview(controller),
                        ),
                      ),
                      if (_focusPointNormalized != null)
                        Positioned(
                          left: (_focusPointNormalized!.dx *
                                  constraints.maxWidth) -
                              28,
                          top: (_focusPointNormalized!.dy *
                                  constraints.maxHeight) -
                              28,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.emeraldBright,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            )
          else if (_cameraDenied)
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 32, 32, 160),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ZapiMascot(
                      mood: ZapiMascotMood.waiting,
                      size: 96,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Câmera sem permissão',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Libere o acesso à câmera para tirar fotos e gravar vídeos aqui. Você também pode escolher pela galeria abaixo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _initCamera,
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Liberar câmera'),
                    ),
                  ],
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Controles superiores: fechar, timer de vídeo, flash, trocar lente
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _CircleGlassButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Fechar câmera',
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    if (_isRecordingVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.fiber_manual_record_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              DateFormatter.formatDuration(_recordDuration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_currentZoom > _minZoom + 0.05)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${_currentZoom.toStringAsFixed(1)}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (cameraReady)
                      _CircleGlassButton(
                        icon: _flashIcon,
                        tooltip: 'Alternar flash',
                        onTap: _cycleFlash,
                      ),
                    if (_cameras.length > 1) ...[
                      const SizedBox(width: 10),
                      _CircleGlassButton(
                        icon: Icons.cameraswitch_rounded,
                        tooltip: 'Trocar câmera',
                        onTap: _switchCamera,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Rodapé: Faixa de mídia recente + botão de captura + galeria completa
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.48),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botão de enviar seleção múltipla, quando houver itens marcados
                    if (_selectedAssets.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, right: 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _exportingSelection
                                ? null
                                : _confirmMultiSelection,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.emerald,
                              foregroundColor: Colors.white,
                            ),
                            icon: _exportingSelection
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 19),
                            label: Text(
                              'Avançar (${_selectedAssets.length})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),

                    // Faixa horizontal de fotos e vídeos recentes
                    SizedBox(
                      height: 76,
                      child: _loadingGallery
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            )
                          : _galleryDenied
                              ? Center(
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _loadRecentMedia(askPermission: true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(
                                      Icons.photo_library_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Liberar fotos recentes do aparelho',
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: _recentAssets.length + 1,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 6),
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: _openFullGallery,
                                        child: Container(
                                          width: 68,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.24),
                                            ),
                                          ),
                                          child: const Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.photo_library_rounded,
                                                color: Colors.white,
                                                size: 22,
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                'Galeria',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    final asset = _recentAssets[index - 1];
                                    final selectedOrder = _selectedAssets
                                        .indexWhere((a) => a.id == asset.id);
                                    final isSelected = selectedOrder >= 0;

                                    return GestureDetector(
                                      onTap: () => _onAssetTap(asset),
                                      child: _GalleryStripTile(
                                        asset: asset,
                                        thumbFuture: _getThumb(asset),
                                        selectedOrder: isSelected
                                            ? selectedOrder + 1
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                    ),

                    const SizedBox(height: 14),

                    // Controles inferiores: Galeria completa, Obturador, Dica
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CircleGlassButton(
                          icon: Icons.photo_library_rounded,
                          tooltip: 'Abrir galeria completa',
                          onTap: _openFullGallery,
                        ),
                        GestureDetector(
                          onTap: cameraReady ? _capturePhoto : null,
                          onLongPressStart: cameraReady && widget.allowVideo
                              ? (_) => _startVideoRecording()
                              : null,
                          onLongPressEnd: widget.allowVideo
                              ? (_) =>
                                  _stopVideoRecording(sendImmediately: true)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: _isRecordingVideo ? 84 : 74,
                            height: _isRecordingVideo ? 84 : 74,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isRecordingVideo
                                    ? const Color(0xFFEF4444)
                                    : Colors.white,
                                width: 4,
                              ),
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                color: _isRecordingVideo
                                    ? const Color(0xFFEF4444)
                                    : Colors.white.withValues(
                                        alpha: cameraReady ? 0.94 : 0.35,
                                      ),
                                shape: _isRecordingVideo
                                    ? BoxShape.rectangle
                                    : BoxShape.circle,
                                borderRadius: _isRecordingVideo
                                    ? BorderRadius.circular(14)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: _cameras.length > 1
                              ? _CircleGlassButton(
                                  icon: Icons.flip_camera_android_rounded,
                                  tooltip: 'Virar câmera',
                                  onTap: _switchCamera,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.allowVideo
                          ? 'Toque para foto · Segure para vídeo'
                          : 'Toque para fotografar',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _GalleryStripTile extends StatelessWidget {
  const _GalleryStripTile({
    required this.asset,
    required this.thumbFuture,
    this.selectedOrder,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbFuture;
  final int? selectedOrder;

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    final isSelected = selectedOrder != null;

    return Container(
      width: 68,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? AppColors.emeraldBright
              : Colors.white.withValues(alpha: 0.18),
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbFuture,
              builder: (context, snap) {
                final bytes = snap.data;
                if (bytes == null) {
                  return const ColoredBox(color: Color(0xFF1F2937));
                }
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            ),
            if (isVideo)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        DateFormatter.formatDuration(
                          Duration(seconds: asset.duration),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$selectedOrder',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FullGallerySheet extends StatefulWidget {
  const _FullGallerySheet({
    required this.allowVideo,
    required this.maxPhotos,
    required this.initialSelectedIds,
  });

  final bool allowVideo;
  final int maxPhotos;
  final List<String> initialSelectedIds;

  @override
  State<_FullGallerySheet> createState() => _FullGallerySheetState();
}

class _FullGallerySheetState extends State<_FullGallerySheet> {
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = const [];
  final List<AssetEntity> _picked = [];
  final Map<String, Uint8List> _thumbs = {};
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() => _loading = true);
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: widget.allowVideo ? RequestType.common : RequestType.image,
        hasAll: true,
      );
      if (!mounted) return;
      _albums = albums;
      if (albums.isNotEmpty) {
        await _selectAlbum(albums.first);
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectAlbum(AssetPathEntity album) async {
    setState(() {
      _selectedAlbum = album;
      _loading = true;
    });
    final list = await album.getAssetListPaged(page: 0, size: 120);
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
  }

  Future<Uint8List?> _thumb(AssetEntity asset) async {
    final cached = _thumbs[asset.id];
    if (cached != null) return cached;
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(220),
      quality: 78,
    );
    if (data != null) {
      if (_thumbs.length > 200) _thumbs.clear();
      _thumbs[asset.id] = data;
    }
    return data;
  }

  Future<void> _onTapAsset(AssetEntity asset) async {
    if (_exporting) return;
    if (asset.type == AssetType.video) {
      if (_picked.isNotEmpty) {
        ZapiToast.showInfo(context, 'Vídeos são enviados um de cada vez.');
        return;
      }
      setState(() => _exporting = true);
      try {
        final file = await asset.file;
        if (!mounted || file == null) return;
        Navigator.pop(
          context,
          ZapiCapturedMedia(
            kind: ZapiCapturedMediaKind.video,
            paths: [file.path],
          ),
        );
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
      return;
    }

    if (widget.maxPhotos <= 1) {
      setState(() => _exporting = true);
      try {
        final file = await asset.file;
        if (!mounted || file == null) return;
        Navigator.pop(
          context,
          ZapiCapturedMedia(
            kind: ZapiCapturedMediaKind.photos,
            paths: [file.path],
          ),
        );
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
      return;
    }

    setState(() {
      final idx = _picked.indexWhere((a) => a.id == asset.id);
      if (idx >= 0) {
        _picked.removeAt(idx);
      } else if (_picked.length < widget.maxPhotos) {
        _picked.add(asset);
      } else {
        ZapiToast.showInfo(
          context,
          'Você pode selecionar até ${widget.maxPhotos} fotos.',
        );
      }
    });
  }

  Future<void> _confirmPicked() async {
    if (_picked.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final paths = <String>[];
      for (final asset in _picked) {
        final f = await asset.file;
        if (f != null && await f.exists()) {
          paths.add(f.path);
        }
      }
      if (!mounted || paths.isEmpty) return;
      Navigator.pop(
        context,
        ZapiCapturedMedia(
          kind: ZapiCapturedMediaKind.photos,
          paths: paths,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                Expanded(
                  child: _albums.isEmpty
                      ? const Text(
                          'Galeria',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : DropdownButtonHideUnderline(
                          child: DropdownButton<AssetPathEntity>(
                            value: _selectedAlbum,
                            dropdownColor: AppColors.darkSurface,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            items: _albums
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(a.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (next) {
                              if (next != null) _selectAlbum(next);
                            },
                          ),
                        ),
                ),
                if (_picked.isNotEmpty)
                  FilledButton(
                    onPressed: _exporting ? null : _confirmPicked,
                    child: Text('Avançar (${_picked.length})'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _assets.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhuma mídia encontrada neste álbum.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(6),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: _assets.length,
                        itemBuilder: (context, idx) {
                          final asset = _assets[idx];
                          final order =
                              _picked.indexWhere((a) => a.id == asset.id);
                          return GestureDetector(
                            onTap: () => _onTapAsset(asset),
                            child: _GalleryStripTile(
                              asset: asset,
                              thumbFuture: _thumb(asset),
                              selectedOrder: order >= 0 ? order + 1 : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
