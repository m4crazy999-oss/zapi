import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../contacts/presentation/providers/contacts_providers.dart';
import '../../data/status_repository.dart';
import '../../domain/status_item.dart';

final statusRepositoryProvider = Provider<StatusRepository>((ref) {
  return StatusRepository(firestore: ref.watch(firebaseFirestoreProvider));
});

final visibleStatusesProvider = StreamProvider<List<StatusItem>>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null || uid.isEmpty) {
    return Stream.value(const []);
  }
  return ref.watch(statusRepositoryProvider).watchVisibleStatuses(uid);
});

final myStatusesProvider = Provider<List<StatusItem>>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid)) ?? '';
  final all = ref.watch(visibleStatusesProvider).value ?? const [];
  return all.where((s) => s.ownerUid == uid && !s.isExpired).toList();
});

final statusViewsProvider =
    StreamProvider.family<List<StatusViewRecord>, String>((ref, statusId) {
  if (statusId.isEmpty) return Stream.value(const []);
  return ref.watch(statusRepositoryProvider).watchStatusViews(statusId);
});

typedef StatusBoardData = ({
  List<ContactStatusGroup> recent,
  List<ContactStatusGroup> viewed,
  List<ContactStatusGroup> muted,
});

final statusBoardProvider = Provider<AsyncValue<StatusBoardData>>((ref) {
  final myUid = ref.watch(authStateProvider.select((s) => s.value?.uid)) ?? '';
  final statusesAsync = ref.watch(visibleStatusesProvider);
  final contactsByUid = ref.watch(contactsByUidProvider);
  final prefs = ref.watch(chatPreferencesProvider);

  return statusesAsync.whenData((allStatuses) {
    final grouped = <String, List<StatusItem>>{};
    for (final status in allStatuses) {
      if (status.ownerUid == myUid || status.isExpired) continue;
      grouped.putIfAbsent(status.ownerUid, () => []).add(status);
    }

    final recent = <ContactStatusGroup>[];
    final viewed = <ContactStatusGroup>[];
    final muted = <ContactStatusGroup>[];

    grouped.forEach((ownerUid, items) {
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final savedContact = contactsByUid[ownerUid];
      final latest = items.last;
      final hasUnviewed =
          items.any((s) => !prefs.isStatusViewed(s.id));
      final isMuted = prefs.isStatusMuted(ownerUid);

      final group = ContactStatusGroup(
        ownerUid: ownerUid,
        displayName: savedContact?.effectiveName ?? latest.ownerName,
        username: savedContact?.username ?? latest.ownerUsername,
        photoBase64: savedContact?.photoBase64 ?? latest.ownerPhotoBase64,
        statuses: items,
        hasUnviewed: hasUnviewed,
        isMuted: isMuted,
      );

      if (isMuted) {
        muted.add(group);
      } else if (hasUnviewed) {
        recent.add(group);
      } else {
        viewed.add(group);
      }
    });

    int byLatestDesc(ContactStatusGroup a, ContactStatusGroup b) =>
        b.latest.createdAt.compareTo(a.latest.createdAt);

    recent.sort(byLatestDesc);
    viewed.sort(byLatestDesc);
    muted.sort(byLatestDesc);

    return (recent: recent, viewed: viewed, muted: muted);
  });
});

final unifiedStatusGroupsProvider =
    Provider<AsyncValue<List<ContactStatusGroup>>>((ref) {
  final boardAsync = ref.watch(statusBoardProvider);
  return boardAsync.whenData(
    (board) => [
      ...board.recent,
      ...board.viewed,
      ...board.muted,
    ],
  );
});
