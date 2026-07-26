import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthController with ChangeNotifier {
  FirebaseAuth _auth = FirebaseAuth.instance;
  String _verificationId = '';

  // Method to initiate phone number verification and send OTP
  Future<void> verifyPhoneNumber(String phoneNumber, BuildContext context) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieve or instantly verifying the code if the device recognizes it
          await _auth.signInWithCredential(credential);
          notifyListeners();
        },
        verificationFailed: (FirebaseAuthException e) {
          // Handle the error
          if (e.code == 'invalid-phone-number') {
            _showSnackBar(context, 'The provided phone number is not valid.');
          } else {
            _showSnackBar(context, 'Verification failed: ${e.message}');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _showSnackBar(context, 'OTP has been sent to your phone.');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      _showSnackBar(context, 'Failed to Verify Phone Number: $e');
    }
  }

  // Method to verify the OTP entered by the user
  Future<void> verifyOTP(String smsCode, BuildContext context) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
      UserCredential userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        _showSnackBar(context, 'Phone number verified successfully!');
        // You can navigate the user to a different screen here
        notifyListeners();
      }
    } catch (e) {
      _showSnackBar(context, 'Failed to verify OTP: $e');
    }
  }

  // Sign out method
  Future<void> signOut(BuildContext context) async {
    await _auth.signOut();
    _showSnackBar(context, 'User signed out successfully');
  }

  // Utility function to show snackbars
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
