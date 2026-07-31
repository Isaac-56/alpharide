import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthController extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _verificationId = '';

  Future<void> verifyPhoneNumber(
    String phoneNumber,
    BuildContext context,
  ) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (
          PhoneAuthCredential credential,
        ) async {
          try {
            await _auth.signInWithCredential(credential);
            notifyListeners();
          } on FirebaseAuthException catch (error) {
            if (!context.mounted) return;

            _showSnackBar(
              context,
              error.message ?? 'Automatic phone verification failed.',
            );
          }
        },
        verificationFailed: (
          FirebaseAuthException error,
        ) {
          if (!context.mounted) return;

          final String message = error.code == 'invalid-phone-number'
              ? 'The provided phone number is not valid.'
              : error.message ?? 'Phone verification failed.';

          _showSnackBar(context, message);
        },
        codeSent: (
          String verificationId,
          int? resendToken,
        ) {
          _verificationId = verificationId;

          if (!context.mounted) return;

          _showSnackBar(
            context,
            'OTP has been sent to your phone.',
          );
        },
        codeAutoRetrievalTimeout: (
          String verificationId,
        ) {
          _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;

      _showSnackBar(
        context,
        error.message ?? 'Unable to verify this phone number.',
      );
    } catch (error) {
      if (!context.mounted) return;

      _showSnackBar(
        context,
        'Unable to verify this phone number.',
      );
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

    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );

      final UserCredential result =
          await _auth.signInWithCredential(credential);

      if (result.user == null) return;

      notifyListeners();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        'Phone number verified successfully.',
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;

      _showSnackBar(
        context,
        error.message ?? 'The verification code is invalid.',
      );
    } catch (error) {
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
      await _auth.signOut();
      notifyListeners();

      if (!context.mounted) return;

      _showSnackBar(
        context,
        'You have been logged out.',
      );
    } catch (error) {
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
