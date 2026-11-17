import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Credentials stay on the backend. Attestation is checked before any paid send.
class WhatsAppAuthService {
  WhatsAppAuthService({
    this.functions,
    this.invoke,
    this.getAppCheckToken,
    this.attestationTimeout = const Duration(seconds: 8),
    this.requestTimeout = const Duration(seconds: 25),
  });

  final FirebaseFunctions? functions;
  final Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> data,
  )? invoke;
  final Future<String?> Function()? getAppCheckToken;
  final Duration attestationTimeout;
  final Duration requestTimeout;

  FirebaseAuthException _attestationError() => FirebaseAuthException(
    code: 'app-verification-required',
    message: kDebugMode && const bool.fromEnvironment('ALPHA_APP_CHECK_DEBUG')
        ? 'Test app setup is incomplete. Register this installation in Firebase App Check, then close and reopen the app. No WhatsApp code was requested.'
        : 'App verification failed. Check your internet connection and reopen the app. If it continues, contact support. No WhatsApp code was requested.',
  );

  Future<void> _checkAttestation() async {
    try {
      final token = await (getAppCheckToken?.call() ??
          FirebaseAppCheck.instance.getToken()).timeout(attestationTimeout);
      // Reject missing/placeholder tokens locally, before calling the backend.
      // Firebase still validates the token signature and app identity.
      if (token == null || token.split('.').length != 3) {
        throw _attestationError();
      }
    } on FirebaseAuthException {
      rethrow;
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'app-verification-timeout',
        message: 'App verification took too long. Check your connection and try again. No WhatsApp code was requested.',
      );
    } on FirebaseException {
      throw _attestationError();
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    await _checkAttestation();
    try {
      if (invoke != null) {
        return await invoke!(name, data).timeout(requestTimeout);
      }
      final callableFunctions = functions ??
          FirebaseFunctions.instanceFor(region: 'africa-south1');
      final result = await callableFunctions
          .httpsCallable(name,
              options: HttpsCallableOptions(timeout: requestTimeout))
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on TimeoutException {
      throw _requestTimeoutError();
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated' ||
          error.code == 'permission-denied') {
        throw _attestationError();
      }
      if (error.code == 'deadline-exceeded') {
        throw _requestTimeoutError();
      }
      throw FirebaseAuthException(
        code: 'whatsapp-verification',
        message: error.code == 'unavailable'
            ? 'Cannot reach the verification service. Check your connection and try again shortly.'
            : (error.message ??
                'WhatsApp verification is unavailable. Please try again.'),
      );
    }
  }

  FirebaseAuthException _requestTimeoutError() => FirebaseAuthException(
    code: 'whatsapp-request-timeout',
    message: 'The verification service took too long to respond. If a WhatsApp code arrives, wait 60 seconds before requesting another. Do not keep tapping Continue.',
  );

  Future<String> requestCode(String phoneNumber, String role) async {
    final result = await _call('requestWhatsAppOtp', {
      'phoneNumber': phoneNumber,
      'role': role,
    });
    final id = result['verificationId'];
    if (id is! String || id.isEmpty) {
      throw FirebaseAuthException(
        code: 'whatsapp-verification',
        message: 'Unable to send the WhatsApp code. Please try again.',
      );
    }
    return id;
  }

  Future<String> verifyCode(String verificationId, String code) async {
    final result = await _call('verifyWhatsAppOtp', {
      'verificationId': verificationId,
      'code': code,
    });
    final token = result['customToken'];
    if (token is! String || token.isEmpty) {
      throw FirebaseAuthException(
        code: 'whatsapp-verification',
        message: 'Unable to complete sign-in. Request a new code.',
      );
    }
    return token;
  }
}
