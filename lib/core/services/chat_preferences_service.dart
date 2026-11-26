import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ChatPreferencesState {
  const ChatPreferencesState({
    this.mutedChatIds = const {},
  });

  final Set<String> mutedChatIds;

  bool isMuted(String chatId) => mutedChatIds.contains(chatId);
}

class ChatPreferencesNotifier extends Notifier<ChatPreferencesState> {
  static const String _fileName = 'zapi_chat_preferences.json';
  bool _loaded = false;

  @override
  ChatPreferencesState build() {
    if (!_loaded) {
      _loaded = true;
      _loadFromDisk();
    }
    return const ChatPreferencesState();
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
      final rawMuted = decoded['mutedChatIds'];
      if (rawMuted is List && ref.mounted) {
        state = ChatPreferencesState(
          mutedChatIds: rawMuted.whereType<String>().toSet(),
        );
      }
    } catch (_) {}
  }

  Future<void> setChatMuted(String chatId, bool muted) async {
    if (chatId.isEmpty) return;
    final next = Set<String>.from(state.mutedChatIds);
    if (muted) {
      next.add(chatId);
    } else {
      next.remove(chatId);
    }
    state = ChatPreferencesState(mutedChatIds: next);
    try {
      final file = await _prefsFile();
      await file.writeAsString(
        jsonEncode({'mutedChatIds': next.toList()}),
        flush: true,
      );
    } catch (_) {}
  }
}

final chatPreferencesProvider =
    NotifierProvider<ChatPreferencesNotifier, ChatPreferencesState>(
  ChatPreferencesNotifier.new,
);
