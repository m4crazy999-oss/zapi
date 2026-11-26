import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/media_cache_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/utils/firebase_error_mapper.dart';
import '../../data/auth_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Mantém o redirecionamento do GoRouter pausado durante cadastro/exclusão
/// para que falhas no Firestore não redirecionem o usuário antes de exibir o erro.
class AuthRedirectHoldNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setHold(bool value) {
    state = value;
  }
}

final authRedirectHoldProvider =
    NotifierProvider<AuthRedirectHoldNotifier, bool>(
  AuthRedirectHoldNotifier.new,
);

class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signInWithEmail(
            email: email,
            password: password,
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

  Future<void> register({
    required String displayName,
    required String username,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    ref.read(authRedirectHoldProvider.notifier).setHold(true);
    try {
      await ref.read(authRepositoryProvider).registerWithEmail(
            displayName: displayName,
            username: username,
            email: email,
            password: password,
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
    } finally {
      if (ref.mounted) {
        ref.read(authRedirectHoldProvider.notifier).setHold(false);
      }
    }
  }

  Future<void> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
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

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
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

  Future<void> signOut() async {
    state = const AsyncLoading();
    try {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      try {
        await ref.read(notificationServiceProvider).clearSession();
      } catch (_) {}
      if (uid != null) {
        try {
          await ref
              .read(presenceServiceProvider)
              .markOfflineBeforeSignOut(uid);
        } catch (_) {}
      }
      try {
        await ref.read(mediaCacheServiceProvider).clearAllCache();
      } catch (_) {}
      await ref.read(authRepositoryProvider).signOut();
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

  Future<void> deleteAccount(String currentPassword) async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.reauthenticateForDeletion(currentPassword: currentPassword);

      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      try {
        await ref.read(notificationServiceProvider).clearSession();
      } catch (_) {}
      if (uid != null) {
        try {
          await ref
              .read(presenceServiceProvider)
              .markOfflineBeforeSignOut(uid);
        } catch (_) {}
      }

      await repo.deleteAccountDataAndAuth();

      try {
        await ref.read(mediaCacheServiceProvider).clearAllCache();
      } catch (_) {}

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
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
