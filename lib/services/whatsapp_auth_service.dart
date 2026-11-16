import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The Bird key and OTP checks stay on the backend. This client receives only
/// an opaque challenge and, after verification, a Firebase custom token.
class WhatsAppAuthService {
  WhatsAppAuthService({this.functions, this.invoke});

  final FirebaseFunctions? functions;
  final Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> data,
  )? invoke;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      if (invoke != null) return await invoke!(name, data);
      final callableFunctions = functions ??
          FirebaseFunctions.instanceFor(region: 'africa-south1');
      final result = await callableFunctions
          .httpsCallable(name,
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 60),
              ))
          .call<Map<String, dynamic>>(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw FirebaseAuthException(
        code: 'whatsapp-verification',
        message: error.message ??
            'WhatsApp verification is unavailable. Please try again.',
      );
    }
  }

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
