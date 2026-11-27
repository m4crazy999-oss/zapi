import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlaybackState {
  const AudioPlaybackState({
    this.activeMessageId,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.errorMessage,
  });

  final String? activeMessageId;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? errorMessage;

  AudioPlaybackState copyWith({
    String? activeMessageId,
    bool clearActiveMessage = false,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    double? speed,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AudioPlaybackState(
      activeMessageId:
          clearActiveMessage ? null : (activeMessageId ?? this.activeMessageId),
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AudioPlaybackController extends Notifier<AudioPlaybackState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  bool _sessionConfigured = false;
  String? _loadedSource;

  @override
  AudioPlaybackState build() {
    ref.onDispose(_disposePlayer);
    return const AudioPlaybackState();
  }

  Future<AudioSession> _ensureSession() async {
    final session = await AudioSession.instance;
    if (!_sessionConfigured) {
      _sessionConfigured = true;
      // Usa perfil de mídia/música para sair no alto-falante principal (nunca no fone de ouvido interno de chamada).
      await session.configure(const AudioSessionConfiguration.music());

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          unawaited(pause());
        }
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        unawaited(pause());
      });
    }
    return session;
  }

  Future<void> _ensurePlayer() async {
    if (_player == null) {
      final player = AudioPlayer();
      _player = player;
      await player.setVolume(1.0);

      _positionSub = player.positionStream.listen((pos) {
        if (!ref.mounted) return;
        state = state.copyWith(position: pos);
      });

      _durationSub = player.durationStream.listen((dur) {
        if (!ref.mounted || dur == null) return;
        state = state.copyWith(duration: dur);
      });

      _playerStateSub = player.playerStateStream.listen((ps) async {
        if (!ref.mounted) return;
        if (ps.processingState == ProcessingState.completed) {
          await player.pause();
          await player.seek(Duration.zero);
          final session = await _ensureSession();
          await session.setActive(false).catchError((_) => false);
          if (ref.mounted) {
            state = state.copyWith(
              isPlaying: false,
              isLoading: false,
              position: Duration.zero,
            );
          }
          return;
        }
        state = state.copyWith(
          isPlaying: ps.playing,
          isLoading: ps.processingState == ProcessingState.loading ||
              ps.processingState == ProcessingState.buffering,
        );
      });
    }

    await _ensureSession();
  }

  Future<void> togglePlay({
    required String messageId,
    required String urlOrPath,
    required bool isLocalFile,
    Duration? fallbackDuration,
    VoidCallback? onStarted,
  }) async {
    await _ensurePlayer();
    final player = _player;
    if (player == null) return;

    final isSameMessage = state.activeMessageId == messageId;

    if (isSameMessage && state.isPlaying) {
      await pause();
      return;
    }

    if (isSameMessage && _loadedSource == urlOrPath) {
      try {
        final session = await _ensureSession();
        await session.setActive(true);
        await player.setVolume(1.0);
        await player.setSpeed(state.speed);
        onStarted?.call();
        await player.play();
      } catch (_) {
        if (ref.mounted) {
          state = state.copyWith(
            isPlaying: false,
            isLoading: false,
            errorMessage: 'Não foi possível retomar este áudio.',
          );
        }
      }
      return;
    }

    try {
      if (isLocalFile) {
        final file = File(urlOrPath);
        if (!await file.exists() || await file.length() <= 64) {
          state = state.copyWith(
            activeMessageId: messageId,
            isLoading: false,
            isPlaying: false,
            errorMessage: 'Arquivo de áudio vazio ou indisponível.',
          );
          return;
        }
      }

      state = state.copyWith(
        activeMessageId: messageId,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: fallbackDuration ?? Duration.zero,
        clearError: true,
      );

      await player.stop();
      if (isLocalFile) {
        await player.setFilePath(urlOrPath);
      } else {
        await player.setUrl(urlOrPath);
      }
      _loadedSource = urlOrPath;
      await player.setVolume(1.0);
      await player.setSpeed(state.speed);

      final session = await _ensureSession();
      final activated = await session.setActive(true);
      if (!activated) {
        state = state.copyWith(
          isLoading: false,
          isPlaying: false,
          errorMessage: 'Não foi possível ativar a saída de som agora.',
        );
        return;
      }

      onStarted?.call();
      await player.play();
    } catch (_) {
      _loadedSource = null;
      if (ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          isPlaying: false,
          errorMessage: 'Não foi possível reproduzir este áudio.',
        );
      }
    }
  }

  Future<void> seek(String messageId, Duration target) async {
    if (state.activeMessageId != messageId || _player == null) return;
    await _player!.seek(target);
  }

  Future<void> cycleSpeed() async {
    final nextSpeed = switch (state.speed) {
      < 1.25 => 1.5,
      < 1.75 => 2.0,
      _ => 1.0,
    };
    state = state.copyWith(speed: nextSpeed);
    await _player?.setSpeed(nextSpeed);
  }

  Future<void> pause() async {
    await _player?.pause();
    try {
      if (_sessionConfigured) {
        final session = await AudioSession.instance;
        await session.setActive(false);
      }
    } catch (_) {}
  }

  /// Pausa qualquer reprodução ativa e libera o foco de áudio antes da gravação.
  Future<void> deactivateForRecording() async {
    try {
      await _player?.pause();
      if (_sessionConfigured) {
        final session = await AudioSession.instance;
        await session.setActive(false);
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _loadedSource = null;
    await _player?.stop();
    try {
      if (_sessionConfigured) {
        final session = await AudioSession.instance;
        await session.setActive(false);
      }
    } catch (_) {}
    if (ref.mounted) {
      state = AudioPlaybackState(speed: state.speed);
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void _disposePlayer() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    unawaited(_player?.dispose());
    _player = null;
    if (_sessionConfigured) {
      AudioSession.instance
          .then((s) => s.setActive(false))
          .catchError((_) => false);
    }
  }
}

final audioPlaybackProvider =
    NotifierProvider<AudioPlaybackController, AudioPlaybackState>(
  AudioPlaybackController.new,
);
