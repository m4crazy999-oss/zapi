import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/public_id_helper.dart';
import '../../../core/utils/validators.dart';
import '../../auth/domain/app_user.dart';
import '../domain/app_contact.dart';

class ContactsRepository {
  ContactsRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _contactsRef(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .collection(AppConstants.contactsSubcollection);
  }

  Stream<List<AppContact>> watchContacts(String uid) {
    return _contactsRef(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      final list = snapshot.docs.map(AppContact.fromFirestore).toList();
      list.sort(
        (a, b) => a.effectiveName
            .toLowerCase()
            .compareTo(b.effectiveName.toLowerCase()),
      );
      return list;
    });
  }

  Future<AppUser> findUserByIdentifier({
    required String rawIdentifier,
    required String currentUid,
  }) async {
    final trimmed = rawIdentifier.trim();
    if (trimmed.isEmpty) {
      throw const AppException('Digite o ID ou @usuário para buscar.');
    }

    try {
      String? targetUid;
      final searchedByPublicId = PublicIdHelper.looksLikePublicId(trimmed);

      if (searchedByPublicId) {
        final normalizedId = PublicIdHelper.normalize(trimmed);
        if (!PublicIdHelper.isValid(normalizedId)) {
          throw const AppException(
            'ID inválido. Digite no formato ZP-XXXXXXXX.',
          );
        }

        final idSnap = await _firestore
            .collection(AppConstants.publicIdsCollection)
            .doc(normalizedId)
            .get();

        if (!idSnap.exists) {
          throw const AppException('Usuário não encontrado.');
        }

        targetUid = idSnap.data()?['uid'] as String?;
      } else {
        final normalized = Validators.normalizeUsername(trimmed);
        final formatError = Validators.validateUsername(normalized);
        if (formatError != null) {
          throw AppException(formatError);
        }

        final usernameSnap = await _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(normalized)
            .get();

        if (!usernameSnap.exists) {
          throw const AppException('Usuário não encontrado.');
        }

        targetUid = usernameSnap.data()?['uid'] as String?;
      }

      if (targetUid == null || targetUid.isEmpty) {
        throw const AppException('Usuário não encontrado.');
      }

      final userSnap = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(targetUid)
          .get();

      if (!userSnap.exists) {
        throw const AppException('Usuário não encontrado.');
      }

      final foundUser = AppUser.fromFirestore(userSnap);
      if (foundUser.uid == currentUid) {
        throw const AppException(
          'Você não pode adicionar a si mesmo aos contatos.',
        );
      }

      if (foundUser.addPrivacy == 'idOnly' && !searchedByPublicId) {
        throw const AppException(
          'Este usuário aceita ser encontrado apenas pelo ID (ZP-...).',
        );
      }
      if (foundUser.addPrivacy == 'usernameOnly' && searchedByPublicId) {
        throw const AppException(
          'Este usuário aceita ser encontrado apenas pelo @usuário.',
        );
      }

      return foundUser;
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> addOrUpdateContact({
    required String ownerUid,
    required AppUser targetUser,
    String? nickname,
    bool isFavorite = false,
  }) async {
    final cleanNickname = nickname?.trim();
    try {
      final writeFuture = _contactsRef(ownerUid).doc(targetUser.uid).set({
        'contactUid': targetUser.uid,
        'nickname':
            (cleanNickname == null || cleanNickname.isEmpty) ? null : cleanNickname,
        'displayName': targetUser.displayName,
        'username': targetUser.username,
        'photoBase64': targetUser.photoBase64,
        'photoUrl': targetUser.photoUrl,
        'about': targetUser.about,
        'isFavorite': isFavorite,
        'addedAt': FieldValue.serverTimestamp(),
      });
      try {
        await writeFuture.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Rede lenta ou offline: já salvo localmente para sincronização imediata.
        unawaited(writeFuture.catchError((_) {}));
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> updateNickname({
    required String ownerUid,
    required String contactUid,
    String? nickname,
  }) async {
    final cleanNickname = nickname?.trim();
    try {
      await _contactsRef(ownerUid).doc(contactUid).update({
        'nickname':
            (cleanNickname == null || cleanNickname.isEmpty) ? null : cleanNickname,
      });
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> setFavorite({
    required String ownerUid,
    required String contactUid,
    required bool isFavorite,
  }) async {
    try {
      await _contactsRef(ownerUid).doc(contactUid).update({
        'isFavorite': isFavorite,
      });
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> removeContact({
    required String ownerUid,
    required String contactUid,
  }) async {
    try {
      await _contactsRef(ownerUid).doc(contactUid).delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
