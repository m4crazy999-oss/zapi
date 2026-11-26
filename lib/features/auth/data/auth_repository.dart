import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/validators.dart';

class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<bool> isUsernameAvailable(String rawUsername) async {
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
      // Pré-checagem rápida para evitar criar conta no Auth se o @usuário já existir.
      final existingUsername = await _firestore
          .collection(AppConstants.usernamesCollection)
          .doc(normalizedUsername)
          .get();
      if (existingUsername.exists) {
        throw const AppException(
          'Este @usuário já está em uso. Escolha outro.',
        );
      }

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

        // Reserva atômica de @usuário e criação do documento de perfil.
        await _firestore.runTransaction((transaction) async {
          final usernameSnap = await transaction.get(usernameRef);
          if (usernameSnap.exists) {
            throw const AppException(
              'Este @usuário acabou de ser reservado por outra pessoa.',
            );
          }

          transaction.set(usernameRef, {
            'uid': user.uid,
            'email': normalizedEmail,
            'createdAt': FieldValue.serverTimestamp(),
          });

          transaction.set(userRef, {
            'uid': user.uid,
            'displayName': cleanName,
            'username': normalizedUsername,
            'email': normalizedEmail,
            'photoBase64': null,
            'photoUrl': null,
            'about': AppConstants.defaultAbout,
            'createdAt': FieldValue.serverTimestamp(),
            'lastSeen': FieldValue.serverTimestamp(),
            'allowEmailSearch': false,
            'blockedUids': <String>[],
            'activeChatId': null,
          });
        });

        await user.updateDisplayName(cleanName);
      } catch (innerError) {
        // Evita conta órfã no Firebase Auth caso a transação falhe.
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> signInWithEmailOrUsername({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    try {
      String emailToUse;
      if (Validators.isEmailFormat(trimmed)) {
        emailToUse = trimmed.toLowerCase();
      } else {
        final normalizedUsername = Validators.normalizeUsername(trimmed);
        final usernameDoc = await _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(normalizedUsername)
            .get();

        if (!usernameDoc.exists) {
          throw const AppException(
            'Nenhuma conta encontrada com esse @usuário.',
          );
        }

        final resolvedEmail = usernameDoc.data()?['email'] as String?;
        if (resolvedEmail == null || resolvedEmail.isEmpty) {
          throw const AppException(
            'Cadastro incompleto para este @usuário. Entre usando seu e-mail.',
          );
        }
        emailToUse = resolvedEmail;
      }

      await _auth.signInWithEmailAndPassword(
        email: emailToUse,
        password: password,
      );

      await updateLastSeen();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
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

  Future<void> updateAllowEmailSearch(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException('Você precisa estar conectado.');
    }
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .update({'allowEmailSearch': enabled});
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> signOut() async {
    try {
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
      final username = userSnap.data()?['username'] as String?;

      // Remove subcoleções (contatos e figurinhas) antes de apagar o documento principal.
      final contactsSnap =
          await userRef.collection(AppConstants.contactsSubcollection).get();
      final stickersSnap =
          await userRef.collection(AppConstants.stickersSubcollection).get();

      final batch = _firestore.batch();
      for (final doc in contactsSnap.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in stickersSnap.docs) {
        batch.delete(doc.reference);
      }
      if (username != null && username.isNotEmpty) {
        final usernameRef = _firestore
            .collection(AppConstants.usernamesCollection)
            .doc(username);
        batch.delete(usernameRef);
      }
      batch.delete(userRef);
      await batch.commit();

      await user.delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
