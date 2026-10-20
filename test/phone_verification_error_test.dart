import 'package:flutter_test/flutter_test.dart';

import 'package:passengerapp/services/phone_verification_error.dart';

void main() {
  test('recognizes Android and web forms of opaque Firebase SMS error 39', () {
    for (final code in ['unknown', 'internal-error', 'error-code:-39']) {
      expect(
        phoneVerificationServiceError(
          code,
          'An internal error has occurred. [ Error code:39 ]',
        ),
        contains('reference 39'),
      );
    }
    expect(
      phoneVerificationServiceError('error-code:-39', null),
      contains('reference 39'),
    );
    expect(phoneVerificationServiceError('invalid-phone-number', null), isNull);
    expect(phoneVerificationServiceError('quota-exceeded', null), isNull);
    expect(
      phoneVerificationServiceError('unknown', 'Error code:390'),
      isNot(contains('reference 39')),
    );
  });
}
