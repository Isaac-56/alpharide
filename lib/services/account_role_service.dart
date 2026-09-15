import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccountRoleService {
  AccountRoleService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'africa-south1');

  static final AccountRoleService instance = AccountRoleService();

  final FirebaseFunctions _functions;

  Future<void> ensurePassengerEligible() =>
      _callRoleFunction('checkAccountRole', 'passenger', requireClaim: false);

  Future<void> claimPassengerRole() =>
      _callRoleFunction('claimAccountRole', 'passenger', requireClaim: true);

  Future<void> _callRoleFunction(
    String functionName,
    String role, {
    required bool requireClaim,
  }) async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable(functionName).call<dynamic>(
        <String, dynamic>{'role': role},
      );
      final Object? data = result.data;

      if (data is Map) {
        final Object? resolvedRole = data['role'];
        final Object? eligible = data['eligible'];
        final Object? claimed = data['claimed'];

        if (eligible == true &&
            (resolvedRole == null || resolvedRole == role) &&
            (!requireClaim || (resolvedRole == role && claimed == true))) {
          return;
        }
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
