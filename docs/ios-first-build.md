# Alpha Ride: first iOS build

Use macOS with Xcode, Flutter and CocoaPods. The GitHub iOS compile check builds an unsigned device app; it does not need account credentials or a real API key, and its output cannot be installed as-is.

1. Pull main and run `flutter pub get`.
2. In Xcode open `ios/Runner.xcworkspace`. In Runner → Signing & Capabilities choose your team and confirm the bundle identifier before registering it. This checkout currently uses `com.example.passengerApp`. For Alpha Ride, choose your final unique production ID before creating an App Store record.
3. In the existing Firebase project `alpha-ride-29708`, register the exact iOS bundle ID. Download that app’s `GoogleService-Info.plist`, place it under `ios/Runner/`, and add it in Xcode to the **Runner target** so it appears in Copy Bundle Resources. iOS startup reads this bundled configuration; Android still uses its existing options. Keep the plist local.
4. Enable Maps SDK for iOS in Google Cloud and create an iOS-restricted key for that bundle ID, restricted to Maps SDK for iOS. Create `ios/Flutter/LocalSecrets.xcconfig` with `ALPHA_IOS_MAPS_API_KEY = YOUR_IOS_KEY`. Keep it local. Configure this before opening the map.
5. Run `flutter build ios --release --no-codesign` for a compile check, then `flutter run -d YOUR_IPHONE_ID` on a paired iPhone with signing configured.

OTP investigation remains on hold. Phone authentication and push notifications on an iPhone still require their own Firebase/APNs configuration and real-device verification. An unsigned compile check does not validate either. Keep App Check enforcement unchanged during the initial build. Driver location permission is foreground only for this first iOS pass; verify background tracking separately before relying on it.
