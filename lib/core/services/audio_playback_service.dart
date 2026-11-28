import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlaybackState {
  const AudioPlaybackState({
    this.activeMessageId,
    this.activeChatId,
    this.activeSenderName,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.errorMessage,
  });

  final String? activeMessageId;
  final String? activeChatId;
  final String? activeSenderName;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? errorMessage;

  AudioPlaybackState copyWith({
    String? activeMessageId,
    String? activeChatId,
    String? activeSenderName,
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
      activeChatId:
          clearActiveMessage ? null : (activeChatId ?? this.activeChatId),
      activeSenderName:
          clearActiveMessage ? null : (activeSenderName ?? this.activeSenderName),
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
  bool _isHandlingCompletion = false;
  int _playbackGen = 0;
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
      // Garante roteamento para mídia no alto-falante principal (AndroidAudioUsage.media), nunca no fone de ouvido de chamada.
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        ),
      );

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
          if (_isHandlingCompletion) return;
          _isHandlingCompletion = true;
          final gen = _playbackGen;
          try {
            await player.pause();
            await player.seek(Duration.zero);
            if (_playbackGen == gen) {
              final session = await _ensureSession();
              await session.setActive(false).catchError((_) => false);
              if (ref.mounted) {
                state = state.copyWith(
                  isPlaying: false,
                  isLoading: false,
                  position: Duration.zero,
                );
              }
            }
          } finally {
            _isHandlingCompletion = false;
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
    String? chatId,
    String? senderName,
    Duration? fallbackDuration,
    VoidCallback? onStarted,
  }) async {
    await _ensurePlayer();
    final player = _player;
    if (player == null) return;

    final isSameMessage = state.activeMessageId == messageId;

    // Usa player.playing diretamente como fonte síncrona da verdade para evitar
    // dessincronização por eventos assíncronos do stream em toques rápidos.
    if (isSameMessage && player.playing) {
      await pause();
      return;
    }

    if (isSameMessage && _loadedSource == urlOrPath) {
      final gen = ++_playbackGen;
      try {
        final session = await _ensureSession();
        await session.setActive(true);
        if (_playbackGen != gen || !ref.mounted) return;
        await player.setVolume(1.0);
        await player.setSpeed(state.speed);
        state = state.copyWith(
          activeChatId: chatId ?? state.activeChatId,
          activeSenderName: senderName ?? state.activeSenderName,
          isPlaying: true,
          clearError: true,
        );
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

    final gen = ++_playbackGen;

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
        activeChatId: chatId,
        activeSenderName: senderName,
        isLoading: true,
        isPlaying: false,
        position: Duration.zero,
        duration: fallbackDuration ?? Duration.zero,
        clearError: true,
      );

      await player.stop();
      if (_playbackGen != gen || !ref.mounted) return;

      if (isLocalFile) {
        await player.setFilePath(urlOrPath);
      } else {
        await player.setUrl(urlOrPath);
      }
      if (_playbackGen != gen || !ref.mounted) return;

      _loadedSource = urlOrPath;
      await player.setVolume(1.0);
      await player.setSpeed(state.speed);

      final session = await _ensureSession();
      final activated = await session.setActive(true);
      if (_playbackGen != gen || !ref.mounted) return;
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
    final maxMs = state.duration.inMilliseconds;
    final clamped = maxMs > 0
        ? Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs))
        : target;
    state = state.copyWith(position: clamped);
    await _player!.seek(clamped);
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
    _playbackGen++;
    if (ref.mounted) {
      state = state.copyWith(isPlaying: false);
    }
    try {
      await _player?.pause();
    } catch (_) {}
  }

  Future<void> resumeCurrent() async {
    final player = _player;
    final id = state.activeMessageId;
    final src = _loadedSource;
    if (player == null || id == null || src == null) return;
    await togglePlay(
      messageId: id,
      urlOrPath: src,
      isLocalFile: !src.startsWith('http'),
      chatId: state.activeChatId,
      senderName: state.activeSenderName,
      fallbackDuration: state.duration,
    );
  }

  /// Pausa qualquer reprodução ativa e libera o foco de áudio antes da gravação.
  Future<void> deactivateForRecording() async {
    _playbackGen++;
    if (ref.mounted) {
      state = state.copyWith(isPlaying: false);
    }
    try {
      await _player?.pause();
      if (_sessionConfigured) {
        final session = await AudioSession.instance;
        await session.setActive(false);
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _playbackGen++;
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
