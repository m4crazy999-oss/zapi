import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'notification_service.dart';

class ChatPreferencesState {
  const ChatPreferencesState({
    this.isLoaded = false,
    this.mutedChatIds = const {},
    this.pinnedChatIds = const {},
    this.chatDrafts = const {},
    this.mutedStatusUids = const {},
    this.viewedStatusIds = const {},
    this.statusPrivacyMode = 'all',
    this.statusCustomUids = const {},
    this.notifSoundEnabled = true,
    this.notifVibrationEnabled = true,
    this.appLockEnabled = false,
    this.appLockPinHash,
    this.appLockUseDeviceBiometric = false,
  });

  final bool isLoaded;
  final Set<String> mutedChatIds;
  final Set<String> pinnedChatIds;
  final Map<String, String> chatDrafts;
  final Set<String> mutedStatusUids;
  final Set<String> viewedStatusIds;
  final String statusPrivacyMode;
  final Set<String> statusCustomUids;
  final bool notifSoundEnabled;
  final bool notifVibrationEnabled;
  final bool appLockEnabled;
  final String? appLockPinHash;
  final bool appLockUseDeviceBiometric;

  bool isMuted(String chatId) => mutedChatIds.contains(chatId);
  bool isPinned(String chatId) => pinnedChatIds.contains(chatId);
  String draftFor(String chatId) => chatDrafts[chatId] ?? '';
  bool isStatusMuted(String uid) => mutedStatusUids.contains(uid);
  bool isStatusViewed(String statusId) => viewedStatusIds.contains(statusId);
  bool get hasAppLockConfigured =>
      appLockEnabled && (appLockPinHash?.isNotEmpty ?? false);

  ChatPreferencesState copyWith({
    bool? isLoaded,
    Set<String>? mutedChatIds,
    Set<String>? pinnedChatIds,
    Map<String, String>? chatDrafts,
    Set<String>? mutedStatusUids,
    Set<String>? viewedStatusIds,
    String? statusPrivacyMode,
    Set<String>? statusCustomUids,
    bool? notifSoundEnabled,
    bool? notifVibrationEnabled,
    bool? appLockEnabled,
    String? appLockPinHash,
    bool clearAppLockPin = false,
    bool? appLockUseDeviceBiometric,
  }) {
    return ChatPreferencesState(
      isLoaded: isLoaded ?? this.isLoaded,
      mutedChatIds: mutedChatIds ?? this.mutedChatIds,
      pinnedChatIds: pinnedChatIds ?? this.pinnedChatIds,
      chatDrafts: chatDrafts ?? this.chatDrafts,
      mutedStatusUids: mutedStatusUids ?? this.mutedStatusUids,
      viewedStatusIds: viewedStatusIds ?? this.viewedStatusIds,
      statusPrivacyMode: statusPrivacyMode ?? this.statusPrivacyMode,
      statusCustomUids: statusCustomUids ?? this.statusCustomUids,
      notifSoundEnabled: notifSoundEnabled ?? this.notifSoundEnabled,
      notifVibrationEnabled:
          notifVibrationEnabled ?? this.notifVibrationEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      appLockPinHash:
          clearAppLockPin ? null : (appLockPinHash ?? this.appLockPinHash),
      appLockUseDeviceBiometric:
          appLockUseDeviceBiometric ?? this.appLockUseDeviceBiometric,
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
      if (!await file.exists()) {
        if (ref.mounted) {
          state = state.copyWith(isLoaded: true);
        }
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        if (ref.mounted) {
          state = state.copyWith(isLoaded: true);
        }
        return;
      }
      final rawMuted = decoded['mutedChatIds'];
      final rawPinned = decoded['pinnedChatIds'];
      final rawDrafts = decoded['chatDrafts'];
      final rawMutedStatus = decoded['mutedStatusUids'];
      final rawViewedStatus = decoded['viewedStatusIds'];
      final rawPrivacyMode = decoded['statusPrivacyMode'];
      final rawCustomUids = decoded['statusCustomUids'];
      final rawSound = decoded['notifSoundEnabled'];
      final rawVibration = decoded['notifVibrationEnabled'];
      final rawLockEnabled = decoded['appLockEnabled'];
      final rawLockPinHash = decoded['appLockPinHash'];
      final rawLockBio = decoded['appLockUseDeviceBiometric'];

      final drafts = <String, String>{};
      if (rawDrafts is Map) {
        rawDrafts.forEach((key, value) {
          if (key is String && value is String && value.trim().isNotEmpty) {
            drafts[key] = value;
          }
        });
      }

      final nextSound = rawSound is bool ? rawSound : true;
      final nextVibration = rawVibration is bool ? rawVibration : true;

      if (ref.mounted) {
        state = ChatPreferencesState(
          isLoaded: true,
          mutedChatIds: rawMuted is List
              ? rawMuted.whereType<String>().toSet()
              : const {},
          pinnedChatIds: rawPinned is List
              ? rawPinned.whereType<String>().toSet()
              : const {},
          chatDrafts: drafts,
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
          notifSoundEnabled: nextSound,
          notifVibrationEnabled: nextVibration,
          appLockEnabled: rawLockEnabled is bool ? rawLockEnabled : false,
          appLockPinHash: rawLockPinHash is String ? rawLockPinHash : null,
          appLockUseDeviceBiometric: rawLockBio is bool ? rawLockBio : false,
        );
        await NotificationService.syncNativeSoundVibration(
          sound: nextSound,
          vibration: nextVibration,
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(isLoaded: true);
      }
    }
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
          'pinnedChatIds': state.pinnedChatIds.toList(),
          'chatDrafts': state.chatDrafts,
          'mutedStatusUids': state.mutedStatusUids.toList(),
          'viewedStatusIds': trimmedViewed,
          'statusPrivacyMode': state.statusPrivacyMode,
          'statusCustomUids': state.statusCustomUids.toList(),
          'notifSoundEnabled': state.notifSoundEnabled,
          'notifVibrationEnabled': state.notifVibrationEnabled,
          'appLockEnabled': state.appLockEnabled,
          'appLockPinHash': state.appLockPinHash,
          'appLockUseDeviceBiometric': state.appLockUseDeviceBiometric,
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

  Future<void> setChatPinned(String chatId, bool pinned) async {
    if (chatId.isEmpty) return;
    final next = Set<String>.from(state.pinnedChatIds);
    if (pinned) {
      next.add(chatId);
    } else {
      next.remove(chatId);
    }
    state = state.copyWith(pinnedChatIds: next);
    await _saveToDisk();
  }

  Future<void> setChatDraft(String chatId, String draft) async {
    if (chatId.isEmpty) return;
    final trimmed = draft.trimRight();
    final existing = state.chatDrafts[chatId] ?? '';
    if (trimmed.trim().isEmpty) {
      if (!state.chatDrafts.containsKey(chatId)) return;
      final next = Map<String, String>.from(state.chatDrafts)..remove(chatId);
      state = state.copyWith(chatDrafts: next);
      await _saveToDisk();
      return;
    }
    if (existing == trimmed) return;
    final capped =
        trimmed.length > 2000 ? trimmed.substring(0, 2000) : trimmed;
    final next = Map<String, String>.from(state.chatDrafts)
      ..[chatId] = capped;
    state = state.copyWith(chatDrafts: next);
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

  Future<void> setNotificationSound(bool enabled) async {
    if (state.notifSoundEnabled == enabled) return;
    state = state.copyWith(notifSoundEnabled: enabled);
    await _saveToDisk();
    await NotificationService.syncNativeSoundVibration(
      sound: state.notifSoundEnabled,
      vibration: state.notifVibrationEnabled,
    );
  }

  Future<void> setNotificationVibration(bool enabled) async {
    if (state.notifVibrationEnabled == enabled) return;
    state = state.copyWith(notifVibrationEnabled: enabled);
    await _saveToDisk();
    await NotificationService.syncNativeSoundVibration(
      sound: state.notifSoundEnabled,
      vibration: state.notifVibrationEnabled,
    );
  }

  Future<void> enableAppLock({
    required String pinHash,
    bool? useDeviceBiometric,
  }) async {
    state = state.copyWith(
      appLockEnabled: true,
      appLockPinHash: pinHash,
      appLockUseDeviceBiometric:
          useDeviceBiometric ?? state.appLockUseDeviceBiometric,
    );
    await _saveToDisk();
  }

  Future<void> setAppLockDeviceBiometric(bool enabled) async {
    if (state.appLockUseDeviceBiometric == enabled) return;
    state = state.copyWith(appLockUseDeviceBiometric: enabled);
    await _saveToDisk();
  }

  Future<void> disableAppLock() async {
    state = state.copyWith(
      appLockEnabled: false,
      clearAppLockPin: true,
      appLockUseDeviceBiometric: false,
    );
    await _saveToDisk();
  }
}

final chatPreferencesProvider =
    NotifierProvider<ChatPreferencesNotifier, ChatPreferencesState>(
  ChatPreferencesNotifier.new,
);
