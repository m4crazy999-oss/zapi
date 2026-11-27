import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/public_id_helper.dart';
import '../../../core/utils/validators.dart';

class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Set<String> _migratedUids = <String>{};

  static const Set<String> _allowedPublicUserFields = <String>{
    'uid',
    'displayName',
    'username',
    'publicId',
    'photoBase64',
    'photoUrl',
    'about',
    'bannerPreset',
    'bannerBase64',
    'createdAt',
    'lastSeen',
    'blockedUids',
    'activeChatId',
    'hideLastSeen',
    'hideReadReceipts',
  };

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<bool> isUsernameAvailable(String rawUsername) async {
    if (_auth.currentUser == null) return true;
    final normalized = Validators.normalizeUsername(rawUsername);
    if (Validators.validateUsername(normalized) != null) {
      return false;
    }
    try {
      final snap = await _firestore
          .collection(AppConstants.usernamesCollection)
          .doc(normalized)
          .get();
      return !snap.exists;
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> registerWithEmail({
    required String displayName,
    required String username,
    required String email,
    required String password,
  }) async {
    final cleanName = displayName.trim();
    final normalizedUsername = Validators.normalizeUsername(username);
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AppException('Não foi possível criar sua conta.');
      }

      try {
        await _createInitialUserDocuments(
          user: user,
          displayName: cleanName,
          username: normalizedUsername,
          email: normalizedEmail,
        );
        _migratedUids.add(user.uid);
        try {
          await user.updateDisplayName(cleanName);
        } catch (_) {}
      } catch (innerError) {
        // Evita conta órfã caso a reserva inicial de perfil no Firestore falhe.
        try {
          await user.delete();
        } catch (_) {
          try {
            await _auth.signOut();
          } catch (_) {}
        }
        rethrow;
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> _createInitialUserDocuments({
    required User user,
    required String displayName,
    required String username,
    required String email,
    bool fallbackUsernameOnConflict = false,
  }) async {
    final userRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid);
    final privateRef = userRef
        .collection(AppConstants.privateSubcollection)
        .doc(AppConstants.privateAccountDoc);

    const maxAttempts = 5;
    var candidateUsername = username;
    var completed = false;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final usernameRef = _firestore
          .collection(AppConstants.usernamesCollection)
          .doc(candidateUsername);
      final candidatePublicId = PublicIdHelper.generate();
      final publicIdRef = _firestore
          .collection(AppConstants.publicIdsCollection)
          .doc(candidatePublicId);

      final outcome = await _firestore.runTransaction<String>((transaction) async {
        final existingUserSnap = await transaction.get(userRef);
        if (existingUserSnap.exists) {
          return 'already_exists';
        }

        final usernameSnap = await transaction.get(usernameRef);
        if (usernameSnap.exists) {
          if (fallbackUsernameOnConflict) {
            return 'username_collision';
          }
          throw const AppException(
            'Este @usuário já está em uso. Escolha outro.',
          );
        }

        final publicIdSnap = await transaction.get(publicIdRef);
        if (publicIdSnap.exists) {
          return 'public_id_collision';
        }

        transaction.set(usernameRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(publicIdRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(userRef, {
          'uid': user.uid,
          'displayName': displayName,
          'username': candidateUsername,
          'publicId': candidatePublicId,
          'photoBase64': null,
          'photoUrl': null,
          'about': AppConstants.defaultAbout,
          'bannerPreset': AppConstants.defaultBannerPreset,
          'bannerBase64': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
          'blockedUids': <String>[],
          'activeChatId': null,
          'hideLastSeen': false,
          'hideReadReceipts': false,
        });

        if (email.isNotEmpty) {
          transaction.set(privateRef, {
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        return 'ok';
      });

      if (outcome == 'ok' || outcome == 'already_exists') {
        completed = true;
        break;
      }
      if (outcome == 'username_collision') {
        final suffix = PublicIdHelper.generate()
            .replaceAll('ZP-', '')
            .substring(0, 4)
            .toLowerCase();
        candidateUsername =
            'zapi_${user.uid.substring(0, 6).toLowerCase()}_$suffix';
      }
    }

    if (!completed) {
      throw const AppException(
        'Não foi possível concluir o cadastro agora. Tente novamente.',
      );
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      await migrateAccountPrivacyIfNeeded(rethrowOnError: false);
      await updateLastSeen();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  String _fallbackUsernameForUid(String uid) {
    final clean = uid.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final prefix = clean.length >= 8 ? clean.substring(0, 8) : clean;
    return 'zapi_$prefix';
  }

  /// Migra contas antigas ou recupera perfis incompletos, garantindo ID público único
  /// (ZP-XXXXXXXX) e mantendo o e-mail apenas no documento privado do dono.
  Future<void> migrateAccountPrivacyIfNeeded({
    bool force = false,
    bool rethrowOnError = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (!force && _migratedUids.contains(user.uid)) return;

    try {
      final userRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid);
      final privateRef = userRef
          .collection(AppConstants.privateSubcollection)
          .doc(AppConstants.privateAccountDoc);

      final userSnap = await userRef.get();
      if (!userSnap.exists) {
        final rawName = (user.displayName ?? '').trim();
        final safeName = rawName.length >= 2 && rawName.length <= 50
            ? rawName
            : 'Usuário Zapi';
        final safeEmail = (user.email ?? '').trim().toLowerCase();
        await _createInitialUserDocuments(
          user: user,
          displayName: safeName,
          username: _fallbackUsernameForUid(user.uid),
          email: safeEmail,
          fallbackUsernameOnConflict: true,
        );
        _migratedUids.add(user.uid);
        return;
      }

      final userData = userSnap.data() ?? <String, dynamic>{};
      final rawUsername = (userData['username'] as String?) ?? '';
      final normalizedUsername = Validators.validateUsername(rawUsername) == null
          ? Validators.normalizeUsername(rawUsername)
          : _fallbackUsernameForUid(user.uid);

      final privateSnap = await privateRef.get();

      final usernameRef = _firestore
          .collection(AppConstants.usernamesCollection)
          .doc(normalizedUsername);
      final usernameSnap = await usernameRef.get();

      final extraKeys = userData.keys
          .where((k) => !_allowedPublicUserFields.contains(k))
          .toList();
      final existingPublicId = (userData['publicId'] as String?) ?? '';
      final hasValidPublicId = PublicIdHelper.isValid(existingPublicId);
      final publicIdRefExisting = hasValidPublicId
          ? _firestore
              .collection(AppConstants.publicIdsCollection)
              .doc(PublicIdHelper.normalize(existingPublicId))
          : null;
      final publicIdSnapExisting =
          publicIdRefExisting != null ? await publicIdRefExisting.get() : null;
      final needsPublicId = !hasValidPublicId ||
          (publicIdSnapExisting != null && !publicIdSnapExisting.exists);

      final needsPrivateDoc = !privateSnap.exists;
      final needsUsernameCreateOrFix = !usernameSnap.exists ||
          (usernameSnap.data()?.containsKey('email') ?? false);
      final needsSchemaRepair = !userData.containsKey('createdAt') ||
          userData['about'] is! String ||
          userData['displayName'] is! String ||
          (userData['displayName'] as String).trim().length < 2 ||
          normalizedUsername != rawUsername;

      if (extraKeys.isEmpty &&
          !needsPublicId &&
          !needsPrivateDoc &&
          !needsUsernameCreateOrFix &&
          !needsSchemaRepair) {
        _migratedUids.add(user.uid);
        return;
      }

      final resolvedEmail = ((privateSnap.data()?['email'] as String?) ??
              (userData['email'] as String?) ??
              user.email ??
              '')
          .trim()
          .toLowerCase();

      const maxAttempts = 5;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final candidateId = !hasValidPublicId
            ? PublicIdHelper.generate()
            : PublicIdHelper.normalize(existingPublicId);
        final publicIdRef = _firestore
            .collection(AppConstants.publicIdsCollection)
            .doc(candidateId);

        final collided = await _firestore.runTransaction<bool>((transaction) async {
          final freshUserSnap = await transaction.get(userRef);
          if (!freshUserSnap.exists) return false;
          final freshData = freshUserSnap.data() ?? <String, dynamic>{};

          final freshPrivateSnap = await transaction.get(privateRef);
          final freshPublicIdSnap = await transaction.get(publicIdRef);
          final freshUsernameSnap = await transaction.get(usernameRef);

          if (freshPublicIdSnap.exists &&
              freshPublicIdSnap.data()?['uid'] != user.uid) {
            return true;
          }

          if (!freshPrivateSnap.exists && resolvedEmail.isNotEmpty) {
            transaction.set(privateRef, {
              'email': resolvedEmail,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          if (!freshPublicIdSnap.exists) {
            transaction.set(publicIdRef, {
              'uid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          final updates = <String, dynamic>{
            'lastSeen': FieldValue.serverTimestamp(),
          };
          for (final key in freshData.keys) {
            if (!_allowedPublicUserFields.contains(key)) {
              updates[key] = FieldValue.delete();
            }
          }
          if (!freshData.containsKey('uid')) {
            updates['uid'] = user.uid;
          }
          if (!freshData.containsKey('createdAt')) {
            updates['createdAt'] = FieldValue.serverTimestamp();
          }
          if (freshData['about'] is! String) {
            updates['about'] = AppConstants.defaultAbout;
          }
          final freshDisplayName = (freshData['displayName'] as String?)?.trim() ?? '';
          if (freshDisplayName.length < 2) {
            final fallbackName = (user.displayName ?? '').trim();
            updates['displayName'] =
                fallbackName.length >= 2 ? fallbackName : 'Usuário Zapi';
          }
          if (!hasValidPublicId) {
            updates['publicId'] = candidateId;
          }
          if (normalizedUsername != rawUsername) {
            updates['username'] = normalizedUsername;
          }

          transaction.update(userRef, updates);

          if (!freshUsernameSnap.exists) {
            transaction.set(usernameRef, {
              'uid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } else if (freshUsernameSnap.data()?.containsKey('email') ?? false) {
            transaction.update(usernameRef, {
              'email': FieldValue.delete(),
            });
          }

          return false;
        });

        if (!collided) {
          _migratedUids.add(user.uid);
          break;
        }
      }
    } catch (error) {
      if (rethrowOnError) {
        throw FirebaseErrorMapper.map(error);
      }
      // Em carregamento silencioso, será tentado novamente ao abrir o app/perfil.
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.setLanguageCode('pt-BR');
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Nenhuma sessão ativa encontrada.');
    }

    final resolvedEmail = await _resolveCurrentEmail(user);
    if (resolvedEmail.isEmpty) {
      throw const AppException(
        'Não foi possível identificar o e-mail desta conta.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: resolvedEmail,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<String> _resolveCurrentEmail(User user) async {
    final authEmail = (user.email ?? '').trim();
    if (authEmail.isNotEmpty) return authEmail;
    try {
      final privateSnap = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .collection(AppConstants.privateSubcollection)
          .doc(AppConstants.privateAccountDoc)
          .get();
      return (privateSnap.data()?['email'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> updateLastSeen() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .update({'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {
      // Falha silenciosa caso ainda não haja conectividade ou documento pronto.
    }
  }

  Future<void> signOut() async {
    try {
      _migratedUids.clear();
      await _auth.signOut();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> reauthenticateForDeletion({
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Nenhuma sessão ativa encontrada.');
    }

    final resolvedEmail = await _resolveCurrentEmail(user);
    if (resolvedEmail.isEmpty) {
      throw const AppException(
        'Não foi possível identificar o e-mail desta conta.',
      );
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: resolvedEmail,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> deleteAccountDataAndAuth() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Nenhuma sessão ativa encontrada.');
    }

    try {
      final userRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? <String, dynamic>{};
      final username = (userData['username'] as String?)?.trim();
      final publicId = (userData['publicId'] as String?)?.trim();

      final refsToDelete = <DocumentReference<Map<String, dynamic>>>[];

      try {
        final contactsSnap =
            await userRef.collection(AppConstants.contactsSubcollection).get();
        for (final doc in contactsSnap.docs) {
          refsToDelete.add(doc.reference);
        }
      } catch (_) {}

      try {
        final stickersSnap =
            await userRef.collection(AppConstants.stickersSubcollection).get();
        for (final doc in stickersSnap.docs) {
          refsToDelete.add(doc.reference);
        }
      } catch (_) {}

      try {
        final statusesSnap = await _firestore
            .collection(AppConstants.statusesCollection)
            .where('ownerUid', isEqualTo: user.uid)
            .get();
        for (final statusDoc in statusesSnap.docs) {
          try {
            final viewsSnap = await statusDoc.reference
                .collection(AppConstants.statusViewsSubcollection)
                .get();
            for (final viewDoc in viewsSnap.docs) {
              refsToDelete.add(viewDoc.reference);
            }
          } catch (_) {}
          refsToDelete.add(statusDoc.reference);
        }
      } catch (_) {}

      final privateRef = userRef
          .collection(AppConstants.privateSubcollection)
          .doc(AppConstants.privateAccountDoc);
      try {
        final privateSnap = await privateRef.get();
        if (privateSnap.exists) {
          refsToDelete.add(privateRef);
        }
      } catch (_) {}

      if (username != null && username.isNotEmpty) {
        final usernameRef = _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(username);
        try {
          final usernameSnap = await usernameRef.get();
          if (usernameSnap.exists &&
              usernameSnap.data()?['uid'] == user.uid) {
            refsToDelete.add(usernameRef);
          }
        } catch (_) {}
      }

      if (publicId != null && PublicIdHelper.isValid(publicId)) {
        final publicIdRef = _firestore
            .collection(AppConstants.publicIdsCollection)
            .doc(PublicIdHelper.normalize(publicId));
        try {
          final publicIdSnap = await publicIdRef.get();
          if (publicIdSnap.exists &&
              publicIdSnap.data()?['uid'] == user.uid) {
            refsToDelete.add(publicIdRef);
          }
        } catch (_) {}
      }

      if (userSnap.exists) {
        refsToDelete.add(userRef);
      }

      if (refsToDelete.isNotEmpty) {
        try {
          const chunkSize = 400;
          for (var i = 0; i < refsToDelete.length; i += chunkSize) {
            final batch = _firestore.batch();
            final end = (i + chunkSize < refsToDelete.length)
                ? i + chunkSize
                : refsToDelete.length;
            for (var j = i; j < end; j++) {
              batch.delete(refsToDelete[j]);
            }
            await batch.commit();
          }
        } catch (_) {
          // Caso alguma subcoleção falhe por regras antigas, garante a remoção individual dos documentos principais.
          for (final ref in refsToDelete) {
            try {
              await ref.delete();
            } catch (_) {}
          }
        }
      }

      _migratedUids.remove(user.uid);
      await user.delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
