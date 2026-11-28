import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../widgets/chat_wallpaper.dart';
import 'app_colors.dart';

class AppearanceState {
  const AppearanceState({
    this.themeMode = ThemeMode.system,
    this.wallpaperId = 'default_pattern',
    this.accentId = 'esmeralda',
  });

  final ThemeMode themeMode;
  final String wallpaperId;
  final String accentId;

  AppearanceState copyWith({
    ThemeMode? themeMode,
    String? wallpaperId,
    String? accentId,
  }) {
    return AppearanceState(
      themeMode: themeMode ?? this.themeMode,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      accentId: accentId ?? this.accentId,
    );
  }
}

class AppearanceNotifier extends Notifier<AppearanceState> {
  static const String _fileName = 'zapi_appearance_prefs.json';
  bool _loaded = false;

  @override
  AppearanceState build() {
    if (!_loaded) {
      _loaded = true;
      _loadFromDisk();
    }
    return const AppearanceState();
  }

  Future<File> _prefsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _prefsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;

      final rawTheme = decoded['themeMode'];
      final rawWallpaper = decoded['wallpaperId'];
      final rawAccent = decoded['accentId'];

      final mode = switch (rawTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      final preset = ChatWallpaperPreset.fromId(
        rawWallpaper is String ? rawWallpaper : null,
      );
      final accent = AccentPreset.fromId(
        rawAccent is String ? rawAccent : null,
      );

      if (ref.mounted) {
        state = AppearanceState(
          themeMode: mode,
          wallpaperId: preset.id,
          accentId: accent.id,
        );
      }
    } catch (_) {}
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _prefsFile();
      final themeStr = switch (state.themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await file.writeAsString(
        jsonEncode({
          'themeMode': themeStr,
          'wallpaperId': state.wallpaperId,
          'accentId': state.accentId,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
    await _saveToDisk();
  }

  Future<void> setWallpaper(String wallpaperId) async {
    final preset = ChatWallpaperPreset.fromId(wallpaperId);
    if (state.wallpaperId == preset.id) return;
    state = state.copyWith(wallpaperId: preset.id);
    await _saveToDisk();
  }

  Future<void> setAccent(AccentPreset preset) async {
    if (state.accentId == preset.id) return;
    state = state.copyWith(accentId: preset.id);
    await _saveToDisk();
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceState>(
  AppearanceNotifier.new,
);

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(appearanceProvider).themeMode,
);

final chatWallpaperProvider = Provider<ChatWallpaperPreset>(
  (ref) => ChatWallpaperPreset.fromId(ref.watch(appearanceProvider).wallpaperId),
);

final accentPresetProvider = Provider<AccentPreset>(
  (ref) => AccentPreset.fromId(ref.watch(appearanceProvider).accentId),
);
