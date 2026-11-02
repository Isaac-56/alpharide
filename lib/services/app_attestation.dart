import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Provider activation does not fetch a token on the splash screen. Firebase
/// SDKs attach and refresh tokens; the backend controls enforcement separately.
Future<void> initializeAppAttestation() async {
  if (kIsWeb ||
      !<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform)) {
    return;
  }
  const bool useDebug =
      kDebugMode && bool.fromEnvironment('ALPHA_APP_CHECK_DEBUG');
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebug
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: useDebug
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } on FirebaseException {
    // No tokens or credentials in logs. Missing attestation cannot bypass an
    // enforced backend; monitoring mode permits staged client distribution.
    debugPrint(
      'App verification initialization failed. Check Firebase App Check configuration.',
    );
  }
}
