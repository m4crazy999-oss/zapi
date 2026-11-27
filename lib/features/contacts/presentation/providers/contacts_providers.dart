import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/contacts_repository.dart';
import '../../domain/app_contact.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(firestore: ref.watch(firebaseFirestoreProvider));
});

final contactsListProvider = StreamProvider<List<AppContact>>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null || uid.isEmpty) {
    return Stream.value(const []);
  }
  return ref.watch(contactsRepositoryProvider).watchContacts(uid);
});

final contactsByUidProvider = Provider<Map<String, AppContact>>((ref) {
  final contacts = ref.watch(contactsListProvider).value ?? const [];
  return {for (final contact in contacts) contact.contactUid: contact};
});

class ContactsSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    state = value;
  }
}

final contactsSearchQueryProvider =
    NotifierProvider<ContactsSearchNotifier, String>(
  ContactsSearchNotifier.new,
);

final filteredContactsProvider = Provider<AsyncValue<List<AppContact>>>((ref) {
  final contactsAsync = ref.watch(contactsListProvider);
  final query = ref.watch(contactsSearchQueryProvider).trim().toLowerCase();

  return contactsAsync.whenData((contacts) {
    if (query.isEmpty) return contacts;
    return contacts.where((contact) {
      return contact.effectiveName.toLowerCase().contains(query) ||
          contact.displayName.toLowerCase().contains(query) ||
          contact.username.toLowerCase().contains(query) ||
          contact.about.toLowerCase().contains(query);
    }).toList();
  });
});

class ContactsController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<AppUser> searchUser(String identifier) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      throw StateError('Sessão expirada.');
    }
    return ref.read(contactsRepositoryProvider).findUserByIdentifier(
          rawIdentifier: identifier,
          currentUid: uid,
        );
  }

  Future<void> addContact({
    required AppUser targetUser,
    String? nickname,
  }) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    state = const AsyncLoading();
    try {
      await ref.read(contactsRepositoryProvider).addOrUpdateContact(
            ownerUid: uid,
            targetUser: targetUser,
            nickname: nickname,
          );
      if (ref.mounted) {
        state = const AsyncData(null);
      }
    } catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<void> updateNickname({
    required String contactUid,
    String? nickname,
  }) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    await ref.read(contactsRepositoryProvider).updateNickname(
          ownerUid: uid,
          contactUid: contactUid,
          nickname: nickname,
        );
  }

  Future<void> setFavorite({
    required String contactUid,
    required bool isFavorite,
  }) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    await ref.read(contactsRepositoryProvider).setFavorite(
          ownerUid: uid,
          contactUid: contactUid,
          isFavorite: isFavorite,
        );
  }

  Future<void> removeContact(String contactUid) async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    await ref.read(contactsRepositoryProvider).removeContact(
          ownerUid: uid,
          contactUid: contactUid,
        );
  }
}

final contactsControllerProvider =
    AsyncNotifierProvider<ContactsController, void>(ContactsController.new);
