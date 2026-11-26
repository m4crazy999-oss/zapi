import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/firebase_error_mapper.dart';
import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  );
});

final currentUserProfileProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null || uid.isEmpty) {
    return Stream.value(null);
  }
  return ref.watch(profileRepositoryProvider).watchProfile(uid);
});

final privateAccountEmailProvider = StreamProvider<String>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null || uid.isEmpty) {
    return Stream.value('');
  }
  return ref.watch(profileRepositoryProvider).watchPrivateEmail(uid);
});

class ProfileController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> syncAccountAndGenerateId() async {
    state = const AsyncLoading();
    try {
      await ref
          .read(authRepositoryProvider)
          .migrateAccountPrivacyIfNeeded(force: true, rethrowOnError: true);
      if (ref.mounted) {
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      final mapped = FirebaseErrorMapper.map(error);
      if (ref.mounted) {
        state = AsyncError(mapped, stackTrace);
      }
      throw mapped;
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String about,
  }) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;

    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            uid: user.uid,
            displayName: displayName,
            username: username,
            about: about,
          );
      if (ref.mounted) {
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      final mapped = FirebaseErrorMapper.map(error);
      if (ref.mounted) {
        state = AsyncError(mapped, stackTrace);
      }
      throw mapped;
    }
  }

  Future<void> uploadPhoto(Uint8List bytes) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;

    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).uploadProfilePhoto(
            uid: user.uid,
            bytes: bytes,
          );
      if (ref.mounted) {
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      final mapped = FirebaseErrorMapper.map(error);
      if (ref.mounted) {
        state = AsyncError(mapped, stackTrace);
      }
      throw mapped;
    }
  }

  Future<void> removePhoto() async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;

    state = const AsyncLoading();
    try {
      await ref.read(profileRepositoryProvider).removeProfilePhoto(user.uid);
      if (ref.mounted) {
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      final mapped = FirebaseErrorMapper.map(error);
      if (ref.mounted) {
        state = AsyncError(mapped, stackTrace);
      }
      throw mapped;
    }
  }

  Future<void> updateBannerPreset(String bannerPreset) async {
    final user = ref.read(firebaseAuthProvider).currentUser;
    if (user == null) return;

    try {
      await ref.read(profileRepositoryProvider).updateBannerPreset(
            uid: user.uid,
            bannerPreset: bannerPreset,
          );
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, void>(ProfileController.new);
