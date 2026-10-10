import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_role_service.dart';

class SessionService {
  SessionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  static final SessionService instance = SessionService();

  static const String _sessionPrefix = 'alpharide_active_session_';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  bool _signInInProgress = false;

  DocumentReference<Map<String, dynamic>> _sessionReference(String uid) {
    return _firestore.collection('user_sessions').doc(uid);
  }

  String _localSessionKey(String uid) => '$_sessionPrefix$uid';

  void beginSignIn() {
    _signInInProgress = true;
  }

  void cancelSignIn() {
    _signInInProgress = false;
  }

  Future<void> activateSession(User user) async {
    _signInInProgress = true;

    try {
      await AccountRoleService.instance.claimPassengerRole();

      final String sessionId = _createSessionId();
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      await preferences.setString(
        _localSessionKey(user.uid),
        sessionId,
      );

      await _sessionReference(user.uid).set(
        <String, dynamic>{
          'activeSessionId': sessionId,
          'uid': user.uid,
          'phoneNumber': user.phoneNumber,
          'platform': 'passenger',
          'signedInAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseAuthException {
      await _auth.signOut();
      rethrow;
    } finally {
      _signInInProgress = false;
    }
  }

  Future<bool> validateExistingSession(
    User user, {
    bool forceServer = false,
  }) async {
    await _waitForSignInTransition();

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String key = _localSessionKey(user.uid);
    final String? localSessionId = preferences.getString(key);

    try {
      // A verified sign-in owns exactly one Alpha product role. Claiming here
      // also migrates sessions created by older app versions.
      // A local session is only persisted after a successful role claim.
      if (localSessionId == null) {
        await AccountRoleService.instance.claimPassengerRole();
      }
    } on FirebaseAuthException catch (error) {
      debugPrint('Unable to confirm the AlphaRide account role: $error');

      if (localSessionId == null ||
          !isTemporaryAccountRoleFailureCode(error.code)) {
        await preferences.remove(key);
        return false;
      }
    }

    if (!forceServer && localSessionId != null) {
      try {
        final cached = await _sessionReference(user.uid)
            .get(const GetOptions(source: Source.cache));
        if (cached.exists &&
            cached.data()?['activeSessionId'] == localSessionId) {
          return true;
        }
      } on FirebaseException {
        // Cache miss: validate with the server instead.
      }
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = forceServer
          ? await _sessionReference(user.uid)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 6))
          : await _sessionReference(user.uid)
                .get()
                .timeout(const Duration(seconds: 6));
      final String? remoteSessionId =
          snapshot.data()?['activeSessionId'] as String?;

      if (!snapshot.exists || remoteSessionId == null) {
        final String newSessionId = localSessionId ?? _createSessionId();

        await preferences.setString(key, newSessionId);
        await _sessionReference(user.uid).set(<String, dynamic>{
          'activeSessionId': newSessionId,
          'uid': user.uid,
          'phoneNumber': user.phoneNumber,
          'platform': 'passenger',
          'signedInAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return true;
      }

      return localSessionId != null && localSessionId == remoteSessionId;
    } on TimeoutException {
      return localSessionId != null;
    } on FirebaseException catch (error) {
      debugPrint('Unable to validate the active session: $error');

      // A temporary network outage must not lock a legitimate user out.
      return localSessionId != null;
    }
  }

  Stream<bool> watchSession(User user) async* {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? localSessionId = preferences.getString(
      _localSessionKey(user.uid),
    );

    if (localSessionId == null) {
      yield false;
      return;
    }

    while (_auth.currentUser?.uid == user.uid) {
      try {
        await for (final DocumentSnapshot<Map<String, dynamic>> snapshot
            in _sessionReference(user.uid).snapshots(
          includeMetadataChanges: true,
        )) {
          if (snapshot.metadata.isFromCache) continue;
          final String? remoteSessionId =
              snapshot.data()?['activeSessionId'] as String?;

          final bool isValid =
              snapshot.exists && localSessionId == remoteSessionId;

          yield isValid;

          if (!isValid) return;
        }

        return;
      } on FirebaseException catch (error) {
        debugPrint('Active-session listener paused: $error');

        final bool isValid = await validateExistingSession(
          user,
          forceServer: true,
        );

        if (!isValid) {
          yield false;
          return;
        }

        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> signOutCurrentDevice() async {
    final User? user = _auth.currentUser;
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    if (user != null) {
      final String key = _localSessionKey(user.uid);
      final String? localSessionId = preferences.getString(key);

      if (localSessionId != null) {
        try {
          await _firestore.runTransaction<void>(
            (Transaction transaction) async {
              final DocumentReference<Map<String, dynamic>> reference =
                  _sessionReference(user.uid);
              final DocumentSnapshot<Map<String, dynamic>> snapshot =
                  await transaction.get(reference);
              final String? remoteSessionId =
                  snapshot.data()?['activeSessionId'] as String?;

              if (remoteSessionId == localSessionId) {
                transaction.delete(reference);
              }
            },
          );
        } on FirebaseException catch (error) {
          debugPrint('Unable to clear the remote session: $error');
        }
      }

      await preferences.remove(key);
    }

    await _auth.signOut();
  }

  Future<void> forceLocalSignOut(User user) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await preferences.remove(_localSessionKey(user.uid));

    if (_auth.currentUser?.uid == user.uid) {
      await _auth.signOut();
    }
  }

  Future<void> _waitForSignInTransition() async {
    for (int attempt = 0; _signInInProgress && attempt < 300; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  String _createSessionId() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
      growable: false,
    );

    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
