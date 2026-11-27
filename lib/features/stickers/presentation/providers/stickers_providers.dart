import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/stickers_repository.dart';
import '../../domain/zapi_sticker.dart';

final stickersRepositoryProvider = Provider<StickersRepository>((ref) {
  return StickersRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    mediaCache: ref.watch(mediaCacheServiceProvider),
  );
});

final userStickersProvider = StreamProvider<List<ZapiSticker>>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  if (authUser == null) return Stream.value(const []);
  return ref.watch(stickersRepositoryProvider).watchUserStickers(authUser.uid);
});

class RecentStickerIdsController extends Notifier<List<String>> {
  @override
  List<String> build() {
    final uid = ref.watch(authStateProvider).value?.uid ?? '';
    if (uid.isNotEmpty) {
      unawaited(_load(uid));
    }
    return const [];
  }

  Future<void> _load(String uid) async {
    final ids = await ref.read(stickersRepositoryProvider).readRecentStickerIds(uid);
    if (ref.mounted) {
      state = ids;
    }
  }

  Future<void> markUsed(ZapiSticker sticker) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final next = await ref
        .read(stickersRepositoryProvider)
        .recordStickerUsed(uid: uid, sticker: sticker);
    if (ref.mounted && next.isNotEmpty) {
      state = next;
    }
  }
}

final recentStickerIdsProvider =
    NotifierProvider<RecentStickerIdsController, List<String>>(
  RecentStickerIdsController.new,
);

/// Retorna exclusivamente as figurinhas criadas ou salvas pelo usuário.
final allAvailableStickersProvider = Provider<List<ZapiSticker>>((ref) {
  return ref.watch(userStickersProvider).value ?? const [];
});
