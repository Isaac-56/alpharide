// SDK interfaces are implemented only by test doubles.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:passengerapp/services/session_service.dart';

class _Auth extends Fake implements FirebaseAuth {}

class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.sessionId);
  final String sessionId;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => <String, dynamic>{
    'activeSessionId': sessionId,
  };
}

class _SessionValues {
  String cachedSession = 'local-session';
  String serverSession = 'local-session';
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  final List<Source?> reads = <Source?>[];
  final _SessionValues values = _SessionValues();
  String get cachedSession => values.cachedSession;
  set cachedSession(String value) => values.cachedSession = value;
  String get serverSession => values.serverSession;
  set serverSession(String value) => values.serverSession = value;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    reads.add(options?.source);
    return _Snapshot(
      options?.source == Source.cache ? cachedSession : serverSession,
    );
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.document);
  final _Document document;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => document;
}

class _Firestore extends Fake implements FirebaseFirestore {
  final _Document document = _Document();
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(document);
}

class _User extends Fake implements User {
  @override
  String get uid => 'passenger';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues(<String, Object>{
      'alpharide_active_session_passenger': 'local-session',
    }),
  );

  test('returning startup uses a matching cache without a role callable or server read', () async {
    final firestore = _Firestore();
    final service = SessionService(auth: _Auth(), firestore: firestore);
    expect(await service.validateExistingSession(_User()), isTrue);
    expect(firestore.document.reads, <Source?>[Source.cache]);
  });

  test(
    'forced validation detects that another installation owns the session',
    () async {
      final firestore = _Firestore();
      firestore.document.serverSession = 'other-device';
      final service = SessionService(auth: _Auth(), firestore: firestore);
      expect(
        await service.validateExistingSession(_User(), forceServer: true),
        isFalse,
      );
      expect(firestore.document.reads, <Source?>[Source.server]);
    },
  );

  test(
    'a stale cache mismatch is checked against the server before logout',
    () async {
      final firestore = _Firestore();
      firestore.document.cachedSession = 'old-cache';
      final service = SessionService(auth: _Auth(), firestore: firestore);
      expect(await service.validateExistingSession(_User()), isTrue);
      expect(firestore.document.reads, <Source?>[Source.cache, null]);
    },
  );
}
