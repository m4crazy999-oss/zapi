import 'dart:async';

import 'package:audio_session/audio_session.dart';
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

  Future<void> _ensurePlayer() async {
    if (_player == null) {
      final player = AudioPlayer();
      _player = player;

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
          await player.seek(Duration.zero);
          await player.pause();
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

    if (!_sessionConfigured) {
      _sessionConfigured = true;
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          pause();
        }
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    }
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
      await player.pause();
      return;
    }

    if (isSameMessage && _loadedSource == urlOrPath) {
      final session = await AudioSession.instance;
      if (await session.setActive(true)) {
        onStarted?.call();
        await player.play();
      }
      return;
    }

    try {
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
      await player.setSpeed(state.speed);

      final session = await AudioSession.instance;
      if (await session.setActive(true)) {
        onStarted?.call();
        await player.play();
      } else {
        state = state.copyWith(isLoading: false);
      }
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
  }

  Future<void> stop() async {
    _loadedSource = null;
    await _player?.stop();
    if (ref.mounted) {
      state = AudioPlaybackState(speed: state.speed);
    }
  }

  void _disposePlayer() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    _player?.dispose();
    _player = null;
  }
}

typedef VoidCallback = void Function();

final audioPlaybackProvider =
    NotifierProvider<AudioPlaybackController, AudioPlaybackState>(
  AudioPlaybackController.new,
);
