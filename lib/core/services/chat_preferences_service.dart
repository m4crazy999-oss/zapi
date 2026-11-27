import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ChatPreferencesState {
  const ChatPreferencesState({
    this.mutedChatIds = const {},
    this.mutedStatusUids = const {},
    this.viewedStatusIds = const {},
    this.statusPrivacyMode = 'all',
    this.statusCustomUids = const {},
  });

  final Set<String> mutedChatIds;
  final Set<String> mutedStatusUids;
  final Set<String> viewedStatusIds;
  final String statusPrivacyMode;
  final Set<String> statusCustomUids;

  bool isMuted(String chatId) => mutedChatIds.contains(chatId);
  bool isStatusMuted(String uid) => mutedStatusUids.contains(uid);
  bool isStatusViewed(String statusId) => viewedStatusIds.contains(statusId);

  ChatPreferencesState copyWith({
    Set<String>? mutedChatIds,
    Set<String>? mutedStatusUids,
    Set<String>? viewedStatusIds,
    String? statusPrivacyMode,
    Set<String>? statusCustomUids,
  }) {
    return ChatPreferencesState(
      mutedChatIds: mutedChatIds ?? this.mutedChatIds,
      mutedStatusUids: mutedStatusUids ?? this.mutedStatusUids,
      viewedStatusIds: viewedStatusIds ?? this.viewedStatusIds,
      statusPrivacyMode: statusPrivacyMode ?? this.statusPrivacyMode,
      statusCustomUids: statusCustomUids ?? this.statusCustomUids,
    );
  }
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
      final rawMutedStatus = decoded['mutedStatusUids'];
      final rawViewedStatus = decoded['viewedStatusIds'];
      final rawPrivacyMode = decoded['statusPrivacyMode'];
      final rawCustomUids = decoded['statusCustomUids'];

      if (ref.mounted) {
        state = ChatPreferencesState(
          mutedChatIds: rawMuted is List
              ? rawMuted.whereType<String>().toSet()
              : const {},
          mutedStatusUids: rawMutedStatus is List
              ? rawMutedStatus.whereType<String>().toSet()
              : const {},
          viewedStatusIds: rawViewedStatus is List
              ? rawViewedStatus.whereType<String>().take(300).toSet()
              : const {},
          statusPrivacyMode: rawPrivacyMode is String &&
                  (rawPrivacyMode == 'all' ||
                      rawPrivacyMode == 'favorites' ||
                      rawPrivacyMode == 'custom')
              ? rawPrivacyMode
              : 'all',
          statusCustomUids: rawCustomUids is List
              ? rawCustomUids.whereType<String>().toSet()
              : const {},
        );
      }
    } catch (_) {}
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _prefsFile();
      final viewedList = state.viewedStatusIds.toList();
      final trimmedViewed = viewedList.length > 300
          ? viewedList.sublist(viewedList.length - 300)
          : viewedList;
      await file.writeAsString(
        jsonEncode({
          'mutedChatIds': state.mutedChatIds.toList(),
          'mutedStatusUids': state.mutedStatusUids.toList(),
          'viewedStatusIds': trimmedViewed,
          'statusPrivacyMode': state.statusPrivacyMode,
          'statusCustomUids': state.statusCustomUids.toList(),
        }),
        flush: true,
      );
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
    state = state.copyWith(mutedChatIds: next);
    await _saveToDisk();
  }

  Future<void> setStatusMuted(String uid, bool muted) async {
    if (uid.isEmpty) return;
    final next = Set<String>.from(state.mutedStatusUids);
    if (muted) {
      next.add(uid);
    } else {
      next.remove(uid);
    }
    state = state.copyWith(mutedStatusUids: next);
    await _saveToDisk();
  }

  Future<void> markStatusViewed(String statusId) async {
    if (statusId.isEmpty || state.viewedStatusIds.contains(statusId)) return;
    final next = Set<String>.from(state.viewedStatusIds)..add(statusId);
    state = state.copyWith(viewedStatusIds: next);
    await _saveToDisk();
  }

  Future<void> setStatusPrivacy({
    required String mode,
    Set<String>? customUids,
  }) async {
    final normalized = (mode == 'favorites' || mode == 'custom') ? mode : 'all';
    state = state.copyWith(
      statusPrivacyMode: normalized,
      statusCustomUids: customUids ?? state.statusCustomUids,
    );
    await _saveToDisk();
  }
}

final chatPreferencesProvider =
    NotifierProvider<ChatPreferencesNotifier, ChatPreferencesState>(
  ChatPreferencesNotifier.new,
);
