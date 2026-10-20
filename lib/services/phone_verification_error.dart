/// Firebase's opaque SMS error is not proof of an invalid number or bad SHA.
String? phoneVerificationServiceError(String code, String? message) {
  final bool error39 = RegExp(
    r'(?:error[ -]?code\s*:?\s*-?39)\b',
    caseSensitive: false,
  ).hasMatch('$code ${message ?? ""}');
  if (error39) {
    return 'SMS verification could not be started for this number (reference 39). '
        'Please try again later. If it continues, contact Alpha support with your mobile network name.';
  }
  if (code == 'internal-error' || code == 'unknown') {
    return 'The verification service is temporarily unavailable. Please try again later.';
  }
  return null;
}
