import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_exceptions.dart';
import '../../../core/utils/firebase_error_mapper.dart';
import '../../../core/utils/media_processor.dart';
import '../../auth/domain/app_user.dart';
import '../../contacts/domain/app_contact.dart';
import '../domain/status_item.dart';

class StatusRepository {
  StatusRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _statusesRef =>
      _firestore.collection(AppConstants.statusesCollection);

  /// Observa os Status ativos (até 24h) visíveis para o usuário atual.
  /// Filtra e limpa automaticamente os próprios Status expirados no Firestore.
  Stream<List<StatusItem>> watchVisibleStatuses(String uid) {
    return _statusesRef
        .where('allowedUids', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      final active = <StatusItem>[];
      final expiredOwnIds = <String>[];

      for (final doc in snapshot.docs) {
        final item = StatusItem.fromFirestore(doc);
        if (item.expiresAt.isAfter(now)) {
          active.add(item);
        } else if (item.ownerUid == uid) {
          expiredOwnIds.add(item.id);
        }
      }

      if (expiredOwnIds.isNotEmpty) {
        unawaited(_cleanupExpiredStatuses(expiredOwnIds));
      }

      active.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return active;
    });
  }

  Future<void> _cleanupExpiredStatuses(List<String> statusIds) async {
    for (final id in statusIds) {
      try {
        await deleteStatus(id);
      } catch (_) {}
    }
  }

  List<String> _buildAllowedUids({
    required String ownerUid,
    required List<AppContact> contacts,
    required StatusPrivacyMode privacyMode,
    required Set<String> customUids,
  }) {
    final allowed = <String>{ownerUid};
    switch (privacyMode) {
      case StatusPrivacyMode.all:
        for (final c in contacts) {
          allowed.add(c.contactUid);
        }
      case StatusPrivacyMode.favorites:
        for (final c in contacts) {
          if (c.isFavorite) {
            allowed.add(c.contactUid);
          }
        }
      case StatusPrivacyMode.custom:
        final validContactIds = {for (final c in contacts) c.contactUid};
        for (final uid in customUids) {
          if (validContactIds.contains(uid)) {
            allowed.add(uid);
          }
        }
    }
    return allowed.take(500).toList();
  }

  Future<void> createTextStatus({
    required AppUser owner,
    required String text,
    required int backgroundColor,
    required List<AppContact> contacts,
    required StatusPrivacyMode privacyMode,
    Set<String> customUids = const {},
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      throw const AppException('Escreva algo para publicar no Status.');
    }
    if (cleanText.length > AppConstants.maxStatusTextLength) {
      throw const AppException(
        'O texto do Status passa do limite permitido.',
      );
    }

    final allowedUids = _buildAllowedUids(
      ownerUid: owner.uid,
      contacts: contacts,
      privacyMode: privacyMode,
      customUids: customUids,
    );

    final docRef = _statusesRef.doc();
    final now = DateTime.now();
    final expiresAt =
        now.add(const Duration(hours: AppConstants.statusDurationHours));

    try {
      await docRef.set({
        'id': docRef.id,
        'ownerUid': owner.uid,
        'ownerName': owner.displayName,
        'ownerUsername': owner.username,
        'ownerPhotoBase64': owner.photoBase64,
        'type': 'text',
        'text': cleanText,
        'backgroundColor': backgroundColor,
        'imageBase64': null,
        'privacyMode': privacyMode.code,
        'allowedUids': allowedUids,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> createPhotoStatus({
    required AppUser owner,
    required String sourceImagePath,
    required String caption,
    required List<AppContact> contacts,
    required StatusPrivacyMode privacyMode,
    Set<String> customUids = const {},
  }) async {
    final cleanCaption = caption.trim();
    if (cleanCaption.length > AppConstants.maxStatusTextLength) {
      throw const AppException(
        'A legenda do Status passa do limite permitido.',
      );
    }

    final Uint8List compressedBytes =
        await MediaProcessor.prepareStatusPhoto(sourceImagePath);
    final imageBase64 = base64Encode(compressedBytes);
    if (compressedBytes.length > AppConstants.maxStatusImageBytes ||
        imageBase64.length > AppConstants.maxStatusImageBase64Chars) {
      throw const AppException(
        'A imagem ficou pesada demais para o Status. Escolha outra foto.',
      );
    }

    final allowedUids = _buildAllowedUids(
      ownerUid: owner.uid,
      contacts: contacts,
      privacyMode: privacyMode,
      customUids: customUids,
    );

    final docRef = _statusesRef.doc();
    final now = DateTime.now();
    final expiresAt =
        now.add(const Duration(hours: AppConstants.statusDurationHours));

    try {
      await docRef.set({
        'id': docRef.id,
        'ownerUid': owner.uid,
        'ownerName': owner.displayName,
        'ownerUsername': owner.username,
        'ownerPhotoBase64': owner.photoBase64,
        'type': 'image',
        'text': cleanCaption,
        'backgroundColor': 0xFF0B141A,
        'imageBase64': imageBase64,
        'privacyMode': privacyMode.code,
        'allowedUids': allowedUids,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }

  Future<void> recordView({
    required StatusItem status,
    required AppUser viewer,
  }) async {
    if (status.ownerUid == viewer.uid) return;
    try {
      await _statusesRef
          .doc(status.id)
          .collection(AppConstants.statusViewsSubcollection)
          .doc(viewer.uid)
          .set({
        'viewerUid': viewer.uid,
        'viewerName': viewer.displayName,
        'viewerPhotoBase64': viewer.photoBase64,
        'viewedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<List<StatusViewRecord>> watchStatusViews(String statusId) {
    return _statusesRef
        .doc(statusId)
        .collection(AppConstants.statusViewsSubcollection)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map(StatusViewRecord.fromFirestore).toList();
      list.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      return list;
    });
  }

  Future<void> deleteStatus(String statusId) async {
    try {
      final statusDoc = _statusesRef.doc(statusId);
      try {
        final viewsSnap = await statusDoc
            .collection(AppConstants.statusViewsSubcollection)
            .get();
        if (viewsSnap.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in viewsSnap.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (_) {}

      await statusDoc.delete();
    } catch (error) {
      throw FirebaseErrorMapper.map(error);
    }
  }
}
