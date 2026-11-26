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
        final usernameRef = _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(normalizedUsername);
        final userRef = _firestore
            .collection(AppConstants.usersCollection)
            .doc(user.uid);
        final privateRef = userRef
            .collection(AppConstants.privateSubcollection)
            .doc(AppConstants.privateAccountDoc);

        const maxAttempts = 5;
        var completed = false;

        for (var attempt = 0; attempt < maxAttempts; attempt++) {
          final candidatePublicId = PublicIdHelper.generate();
          final publicIdRef = _firestore
              .collection(AppConstants.publicIdsCollection)
              .doc(candidatePublicId);

          final collided = await _firestore.runTransaction<bool>((transaction) async {
            final usernameSnap = await transaction.get(usernameRef);
            if (usernameSnap.exists) {
              throw const AppException(
                'Este @usuário já está em uso. Escolha outro.',
              );
            }

            final publicIdSnap = await transaction.get(publicIdRef);
            if (publicIdSnap.exists) {
              return true;
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
              'displayName': cleanName,
              'username': normalizedUsername,
              'publicId': candidatePublicId,
              'photoBase64': null,
              'photoUrl': null,
              'about': AppConstants.defaultAbout,
              'createdAt': FieldValue.serverTimestamp(),
              'lastSeen': FieldValue.serverTimestamp(),
              'blockedUids': <String>[],
              'activeChatId': null,
            });

            transaction.set(privateRef, {
              'email': normalizedEmail,
              'updatedAt': FieldValue.serverTimestamp(),
            });

            return false;
          });

          if (!collided) {
            completed = true;
            break;
          }
        }

        if (!completed) {
          throw const AppException(
            'Não foi possível concluir o cadastro agora. Tente novamente.',
          );
        }

        _migratedUids.add(user.uid);
        await user.updateDisplayName(cleanName);
      } catch (innerError) {
        // Evita conta órfã caso a reserva inicial de perfil falhe.
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
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

      await migrateAccountPrivacyIfNeeded();
      await updateLastSeen();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  /// Migra contas antigas removendo e-mail/busca por e-mail dos documentos públicos,
  /// salvando o e-mail somente no documento privado do dono e gerando ID público único.
  Future<void> migrateAccountPrivacyIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_migratedUids.contains(user.uid)) return;

    try {
      final userRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid);
      final privateRef = userRef
          .collection(AppConstants.privateSubcollection)
          .doc(AppConstants.privateAccountDoc);

      final userSnap = await userRef.get();
      if (!userSnap.exists) return;

      final userData = userSnap.data() ?? <String, dynamic>{};
      final username = (userData['username'] as String?) ?? '';
      final privateSnap = await privateRef.get();

      DocumentReference<Map<String, dynamic>>? usernameRef;
      DocumentSnapshot<Map<String, dynamic>>? usernameSnap;
      if (username.isNotEmpty) {
        usernameRef = _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(username);
        usernameSnap = await usernameRef.get();
      }

      final hasLegacyEmail = userData.containsKey('email');
      final hasLegacyAllowEmailSearch = userData.containsKey('allowEmailSearch');
      final existingPublicId = (userData['publicId'] as String?) ?? '';
      final needsPublicId = !PublicIdHelper.isValid(existingPublicId);
      final needsPrivateDoc = !privateSnap.exists;
      final needsUsernameClean = usernameSnap != null &&
          usernameSnap.exists &&
          (usernameSnap.data()?.containsKey('email') ?? false);

      if (!hasLegacyEmail &&
          !hasLegacyAllowEmailSearch &&
          !needsPublicId &&
          !needsPrivateDoc &&
          !needsUsernameClean) {
        _migratedUids.add(user.uid);
        return;
      }

      final resolvedEmail = (privateSnap.data()?['email'] as String?) ??
          (userData['email'] as String?) ??
          user.email ??
          '';

      const maxAttempts = 5;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final candidateId = needsPublicId ? PublicIdHelper.generate() : existingPublicId;
        final publicIdRef = _firestore
            .collection(AppConstants.publicIdsCollection)
            .doc(candidateId);

        final collided = await _firestore.runTransaction<bool>((transaction) async {
          final freshUserSnap = await transaction.get(userRef);
          if (!freshUserSnap.exists) return false;
          final freshData = freshUserSnap.data() ?? <String, dynamic>{};

          final freshPrivateSnap = await transaction.get(privateRef);
          final freshPublicIdSnap =
              needsPublicId ? await transaction.get(publicIdRef) : null;
          final freshUsernameSnap =
              usernameRef != null ? await transaction.get(usernameRef) : null;

          if (needsPublicId &&
              freshPublicIdSnap != null &&
              freshPublicIdSnap.exists &&
              freshPublicIdSnap.data()?['uid'] != user.uid) {
            return true;
          }

          if (!freshPrivateSnap.exists && resolvedEmail.isNotEmpty) {
            transaction.set(privateRef, {
              'email': resolvedEmail.trim().toLowerCase(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          if (needsPublicId) {
            transaction.set(publicIdRef, {
              'uid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          final updates = <String, dynamic>{
            'lastSeen': FieldValue.serverTimestamp(),
          };
          if (freshData.containsKey('email')) {
            updates['email'] = FieldValue.delete();
          }
          if (freshData.containsKey('allowEmailSearch')) {
            updates['allowEmailSearch'] = FieldValue.delete();
          }
          if (needsPublicId) {
            updates['publicId'] = candidateId;
          }
          transaction.update(userRef, updates);

          if (usernameRef != null &&
              freshUsernameSnap != null &&
              freshUsernameSnap.exists &&
              (freshUsernameSnap.data()?.containsKey('email') ?? false)) {
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
    } catch (_) {
      // Será tentado novamente na próxima abertura de sessão.
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

  Future<void> deleteAccount({required String currentPassword}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AppException('Nenhuma sessão ativa encontrada.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      final userRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? <String, dynamic>{};
      final username = userData['username'] as String?;
      final publicId = userData['publicId'] as String?;

      final contactsSnap =
          await userRef.collection(AppConstants.contactsSubcollection).get();
      final stickersSnap =
          await userRef.collection(AppConstants.stickersSubcollection).get();
      final privateRef = userRef
          .collection(AppConstants.privateSubcollection)
          .doc(AppConstants.privateAccountDoc);

      final batch = _firestore.batch();
      for (final doc in contactsSnap.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in stickersSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(privateRef);

      if (username != null && username.isNotEmpty) {
        final usernameRef = _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(username);
        batch.delete(usernameRef);
      }
      if (publicId != null && PublicIdHelper.isValid(publicId)) {
        final publicIdRef = _firestore
            .collection(AppConstants.publicIdsCollection)
            .doc(publicId);
        batch.delete(publicIdRef);
      }
      batch.delete(userRef);
      await batch.commit();

      _migratedUids.remove(user.uid);
      await user.delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
