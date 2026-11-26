import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/session_service.dart';
import '../services/whatsapp_auth_service.dart';

class AuthController extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _verificationId = '';

  Future<void> verifyPhoneNumber(
    String phoneNumber,
    BuildContext context,
  ) async {
    try {
      _verificationId = await WhatsAppAuthService()
          .requestCode(phoneNumber, 'passenger');
      if (context.mounted) {
        _showSnackBar(context, 'Your verification code was sent on WhatsApp.');
      }
    } on FirebaseAuthException catch (error) {
      if (context.mounted) {
        _showSnackBar(context, error.message ?? 'Unable to send the code.');
      }
    }
  }

  Future<void> verifyOTP(
    String smsCode,
    BuildContext context,
  ) async {
    if (_verificationId.isEmpty) {
      _showSnackBar(
        context,
        'Please request a new verification code.',
      );
      return;
    }

    SessionService.instance.beginSignIn();

    try {
      final token = await WhatsAppAuthService()
          .verifyCode(_verificationId, smsCode);
      final UserCredential result = await _auth.signInWithCustomToken(token);
      final User? user = result.user;

      if (user == null) {
        throw StateError('Firebase did not return a signed-in user.');
      }

      await user.getIdToken(true);
      await SessionService.instance.activateSession(user);
      notifyListeners();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        'Phone number verified successfully.',
      );
    } on FirebaseAuthException catch (error) {
      SessionService.instance.cancelSignIn();
      await _auth.signOut();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        error.message ?? 'The verification code is invalid.',
      );
    } catch (_) {
      SessionService.instance.cancelSignIn();
      await _auth.signOut();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        'Unable to verify the code.',
      );
    }
  }

  Future<void> signOut(
    BuildContext context,
  ) async {
    try {
      await SessionService.instance.signOutCurrentDevice();
      notifyListeners();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        'You have been logged out.',
      );
    } catch (_) {
      if (!context.mounted) return;

      _showSnackBar(
        context,
        'Unable to log out. Please try again.',
      );
    }
  }

  void _showSnackBar(
    BuildContext context,
    String message,
  ) {
    if (!context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }
}
