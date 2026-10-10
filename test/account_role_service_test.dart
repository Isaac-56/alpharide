import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/services/account_role_service.dart';

void main() {
  test('temporary passenger role failures preserve an existing session', () {
    expect(
      isTemporaryAccountRoleFailureCode('account-role-unavailable'),
      isTrue,
    );
    expect(
      isTemporaryAccountRoleFailureCode('account-role-deadline-exceeded'),
      isTrue,
    );
    expect(
      isTemporaryAccountRoleFailureCode('account-role-internal'),
      isTrue,
    );
    expect(
      isTemporaryAccountRoleFailureCode('account-role-resource-exhausted'),
      isTrue,
    );
  });

  test('passenger role conflicts fail closed', () {
    expect(
      isTemporaryAccountRoleFailureCode('account-role-conflict'),
      isFalse,
    );
    expect(
      isTemporaryAccountRoleFailureCode('account-role-failed-precondition'),
      isFalse,
    );
    expect(
      isTemporaryAccountRoleFailureCode('account-role-response-invalid'),
      isFalse,
    );
  });
}
