import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/validators.dart';
import '../../auth/domain/app_user.dart';

class ProfileRepository {
  ProfileRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<AppUser?> watchProfile(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Stream<String> watchPrivateEmail(String uid) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .collection(AppConstants.privateSubcollection)
        .doc(AppConstants.privateAccountDoc)
        .snapshots()
        .map((doc) {
      final email = (doc.data()?['email'] as String?)?.trim() ?? '';
      if (email.isNotEmpty) return email;
      return _auth.currentUser?.email ?? '';
    });
  }

  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String username,
    required String about,
  }) async {
    final cleanName = displayName.trim();
    final normalizedUsername = Validators.normalizeUsername(username);
    final cleanAbout = about.trim().isEmpty
        ? AppConstants.defaultAbout
        : about.trim();

    try {
      final userRef = _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid);
      final newUsernameRef = _firestore
          .collection(AppConstants.usernamesCollection)
          .doc(normalizedUsername);

      await _firestore.runTransaction((transaction) async {
        final userSnap = await transaction.get(userRef);
        if (!userSnap.exists) {
          throw const AppException('Perfil não encontrado.');
        }

        final data = userSnap.data()!;
        final currentUsername = (data['username'] as String?) ?? '';

        if (normalizedUsername != currentUsername) {
          final newUsernameSnap = await transaction.get(newUsernameRef);
          if (newUsernameSnap.exists) {
            throw const AppException(
              'Este @usuário já está em uso. Escolha outro.',
            );
          }

          if (currentUsername.isNotEmpty) {
            final oldUsernameRef = _firestore
                .collection(AppConstants.usernamesCollection)
                .doc(currentUsername);
            transaction.delete(oldUsernameRef);
          }

          transaction.set(newUsernameRef, {
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        transaction.update(userRef, {
          'displayName': cleanName,
          'username': normalizedUsername,
          'about': cleanAbout,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      });

      await _auth.currentUser?.updateDisplayName(cleanName);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<String> uploadProfilePhoto({
    required String uid,
    required Uint8List bytes,
  }) async {
    if (bytes.length > AppConstants.maxProfilePhotoBytes) {
      throw const AppException(
        'A foto selecionada é muito grande. Tente escolher outra imagem.',
      );
    }

    try {
      final encoded = base64Encode(bytes);
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'photoBase64': encoded,
        'photoUrl': null,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      return encoded;
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> removeProfilePhoto(String uid) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'photoBase64': null,
        'photoUrl': null,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      await _auth.currentUser?.updatePhotoURL(null);
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
