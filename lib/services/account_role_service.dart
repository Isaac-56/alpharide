import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountRoleService {
  AccountRoleService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'africa-south1');

  static final AccountRoleService instance = AccountRoleService();

  final FirebaseFunctions _functions;

  Future<void> claimPassengerRole() => _claimRole('passenger');

  Future<void> _claimRole(String role) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable('claimAccountRole').call<dynamic>(
        <String, dynamic>{'role': role},
      );
      final Object? data = result.data;
      if (data is Map && data['role'] == role) {
        return;
      }

      throw FirebaseAuthException(
        code: 'account-role-response-invalid',
        message: 'AlphaRide could not confirm your account type.',
      );
    } on FirebaseFunctionsException catch (error) {
      final String? existingRole = _existingRole(error.details);

      if (error.code == 'failed-precondition' && existingRole == 'driver') {
        throw FirebaseAuthException(
          code: 'account-role-conflict',
          message:
              'This phone number is already registered with Alpha Plus. Use a different number for AlphaRide.',
        );
      }

      throw FirebaseAuthException(
        code: 'account-role-${error.code}',
        message:
            error.message ?? 'AlphaRide could not confirm your account type.',
      );
    }
  }

  String? _existingRole(Object? details) {
    if (details is Map) {
      final Object? value = details['existingRole'];
      if (value is String) {
        return value;
      }
    }
    return null;
  }
}
