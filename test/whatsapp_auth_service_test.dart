import 'dart:async';

import 'package:passengerapp/services/whatsapp_auth_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send and check use callable backend without client credentials', () async {
    final calls = <String>[];
    final service = WhatsAppAuthService(getAppCheckToken: () async => 'header.payload.signature', invoke: (name, data) async {
      calls.add(name);
      if (name == 'requestWhatsAppOtp') {
        expect(data, {'phoneNumber': '+211922049035', 'role': 'driver'});
        return {'verificationId': 'opaque-challenge'};
      }
      expect(data, {'verificationId': 'opaque-challenge', 'code': '123456'});
      return {'customToken': 'firebase-token'};
    });
    final id = await service.requestCode('+211922049035', 'driver');
    expect(await service.verifyCode(id, '123456'), 'firebase-token');
    expect(calls, ['requestWhatsAppOtp', 'verifyWhatsAppOtp']);
  });

  test('provider failures do not become successful login tokens', () async {
    final service = WhatsAppAuthService(getAppCheckToken: () async => 'header.payload.signature', invoke: (_, data) async {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'This code expired. Request a new code.',
      );
    });
    await expectLater(service.verifyCode('challenge', '123456'),
      throwsA(isA<FirebaseAuthException>().having(
        (error) => error.message, 'message',
        'This code expired. Request a new code.',
      )));
  });

  test('malformed success response is rejected', () async {
    final service = WhatsAppAuthService(getAppCheckToken: () async => 'header.payload.signature', invoke: (_, data) async => {});
    await expectLater(service.requestCode('+211922049035', 'passenger'),
      throwsA(isA<FirebaseAuthException>()));
    await expectLater(service.verifyCode('challenge', '123456'),
      throwsA(isA<FirebaseAuthException>()));
  });

  test('missing attestation blocks paid requests', () async {
    var calls = 0;
    final service = WhatsAppAuthService(
      getAppCheckToken: () async => null,
      invoke: (_, data) async { calls++; return {}; },
    );
    await expectLater(service.requestCode('+211922049035', 'passenger'),
      throwsA(isA<FirebaseAuthException>().having(
        (error) => error.code, 'code', 'app-verification-required')));
    expect(calls, 0);
  });

  test('slow attestation fails promptly without sending OTP', () async {
    var calls = 0;
    final pending = Completer<String?>();
    final service = WhatsAppAuthService(
      getAppCheckToken: () => pending.future,
      attestationTimeout: const Duration(milliseconds: 5),
      invoke: (_, data) async { calls++; return {}; },
    );
    await expectLater(service.requestCode('+211922049035', 'passenger'),
      throwsA(isA<FirebaseAuthException>().having(
        (error) => error.code, 'code', 'app-verification-timeout')));
    pending.complete('header.payload.signature');
    expect(calls, 0);
  });

  test('slow callable is not retried automatically', () async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    final service = WhatsAppAuthService(
      getAppCheckToken: () async => 'header.payload.signature',
      requestTimeout: const Duration(milliseconds: 5),
      invoke: (_, data) { calls++; return pending.future; },
    );
    await expectLater(service.requestCode('+211922049035', 'passenger'),
      throwsA(isA<FirebaseAuthException>().having(
        (error) => error.code, 'code', 'whatsapp-request-timeout')));
    pending.complete({'verificationId': 'late'});
    expect(calls, 1);
  });
}
