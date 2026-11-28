import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../constants/app_constants.dart';

class UserPresence {
  const UserPresence({
    required this.online,
    this.lastSeen,
  });

  final bool online;
  final DateTime? lastSeen;

  static const offline = UserPresence(online: false);
}

class PresenceService {
  PresenceService({
    required FirebaseAuth auth,
    required FirebaseDatabase database,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _database = database,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final FirebaseFirestore _firestore;

  StreamSubscription<DatabaseEvent>? _connectedSub;
  final _connectionController = StreamController<bool>.broadcast();
  String? _boundUid;
  bool _isResumed = true;
  bool _hideLastSeen = false;
  bool _isServerConnected = true;

  bool get isServerConnected => _isServerConnected;

  Stream<bool> watchServerConnection() async* {
    yield _isServerConnected;
    yield* _connectionController.stream;
  }

  void _updateServerConnection(bool connected) {
    if (_isServerConnected == connected) return;
    _isServerConnected = connected;
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  Future<void> setHideLastSeen(bool hidden) async {
    if (_hideLastSeen == hidden) return;
    _hideLastSeen = hidden;
    final uid = _boundUid ?? _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final userPresenceRef =
          _database.ref('${AppConstants.rtdbPresencePath}/$uid');
      if (hidden) {
        await userPresenceRef.set({'online': false});
      } else if (_isResumed) {
        await userPresenceRef.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await userPresenceRef.set({
          'online': true,
          'lastSeen': ServerValue.timestamp,
        });
      }
    } catch (_) {}
  }

  Future<void> bindUser(String uid) async {
    if (_boundUid == uid && _connectedSub != null) return;
    await unbind();
    _boundUid = uid;
    _isResumed = true;

    try {
      final connectedRef = _database.ref('.info/connected');
      _connectedSub = connectedRef.onValue.listen((event) async {
        final connected = event.snapshot.value == true;
        _updateServerConnection(connected);
        if (!connected || _boundUid != uid) return;

        final userPresenceRef =
            _database.ref('${AppConstants.rtdbPresencePath}/$uid');
        try {
          if (_hideLastSeen) {
            await userPresenceRef.set({'online': false});
            return;
          }
          await userPresenceRef.onDisconnect().set({
            'online': false,
            'lastSeen': ServerValue.timestamp,
          });
          if (_isResumed) {
            await userPresenceRef.set({
              'online': true,
              'lastSeen': ServerValue.timestamp,
            });
          }
        } catch (_) {
          // Realtime Database pode ainda não estar ativado ou estar temporariamente offline.
        }
      });
    } catch (_) {
      // Evita falha fatal se o Realtime Database ainda não tiver URL configurada.
    }
  }

  Future<void> setAppForeground(bool isForeground) async {
    _isResumed = isForeground;
    final uid = _boundUid ?? _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final userPresenceRef =
          _database.ref('${AppConstants.rtdbPresencePath}/$uid');
      if (_hideLastSeen) {
        await userPresenceRef.set({'online': false});
      } else if (isForeground) {
        await userPresenceRef.onDisconnect().set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
        await userPresenceRef.set({
          'online': true,
          'lastSeen': ServerValue.timestamp,
        });
      } else {
        await userPresenceRef.set({
          'online': false,
          'lastSeen': ServerValue.timestamp,
        });
      }
    } catch (_) {}

    if (!isForeground && !_hideLastSeen) {
      try {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .update({'lastSeen': FieldValue.serverTimestamp()});
      } catch (_) {}
    }
  }

  Future<void> markOfflineBeforeSignOut(String uid) async {
    try {
      await _database.ref('${AppConstants.rtdbPresencePath}/$uid').set({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {}
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({
        'lastSeen': FieldValue.serverTimestamp(),
        'activeChatId': null,
      });
    } catch (_) {}
    await unbind();
  }

  Future<void> unbind() async {
    await _connectedSub?.cancel();
    _connectedSub = null;
    _boundUid = null;
  }

  Future<void> dispose() async {
    await unbind();
    await _connectionController.close();
  }

  Stream<UserPresence> watchUserPresence(String targetUid) {
    final controller = StreamController<UserPresence>();
    StreamSubscription<DatabaseEvent>? rtdbSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? firestoreSub;

    bool hasRtdbValue = false;
    DateTime? firestoreLastSeen;

    void emitCombined(bool online, DateTime? rtdbLastSeen) {
      if (controller.isClosed) return;
      controller.add(
        UserPresence(
          online: online,
          lastSeen: rtdbLastSeen ?? firestoreLastSeen,
        ),
      );
    }

    firestoreSub = _firestore
        .collection(AppConstants.usersCollection)
        .doc(targetUid)
        .snapshots()
        .listen(
      (doc) {
        final ts = doc.data()?['lastSeen'] as Timestamp?;
        firestoreLastSeen = ts?.toDate();
        if (!hasRtdbValue) {
          emitCombined(false, firestoreLastSeen);
        }
      },
      onError: (_) {},
    );

    try {
      rtdbSub = _database
          .ref('${AppConstants.rtdbPresencePath}/$targetUid')
          .onValue
          .listen(
        (event) {
          final raw = event.snapshot.value;
          if (raw is Map) {
            hasRtdbValue = true;
            final online = raw['online'] == true;
            final lastSeenRaw = raw['lastSeen'];
            DateTime? parsed;
            if (lastSeenRaw is int) {
              parsed = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
            } else if (lastSeenRaw is double) {
              parsed = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw.toInt());
            }
            emitCombined(online, parsed);
          } else {
            hasRtdbValue = false;
            emitCombined(false, firestoreLastSeen);
          }
        },
        onError: (_) {
          emitCombined(false, firestoreLastSeen);
        },
      );
    } catch (_) {
      emitCombined(false, firestoreLastSeen);
    }

    controller.onCancel = () async {
      await rtdbSub?.cancel();
      await firestoreSub?.cancel();
      await controller.close();
    };

    return controller.stream;
  }
}

final firebaseDatabaseProvider = Provider<FirebaseDatabase>(
  (ref) => FirebaseDatabase.instance,
);

final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService(
    auth: ref.watch(firebaseAuthProvider),
    database: ref.watch(firebaseDatabaseProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final userPresenceProvider =
    StreamProvider.autoDispose.family<UserPresence, String>((ref, targetUid) {
  return ref.watch(presenceServiceProvider).watchUserPresence(targetUid);
});

final serverConnectionProvider = StreamProvider<bool>((ref) {
  return ref.watch(presenceServiceProvider).watchServerConnection();
});
