# WhatsApp-distributed Android release repair

`prepare_whatsapp_release.ps1` updates both existing feature branches, verifies the old release APK certificates, repairs supported Firebase/Maps configuration, deploys first-letter passenger search, builds both APKs, and verifies the new signatures before opening a fresh export folder.

Run on the Windows computer that already contains `C:\Projects\Alpha`, `C:\Projects\alpha_plus`, the existing release APKs, Android SDK, Java, Flutter, Node 22, Firebase CLI and an owner-authorized gcloud session. Keep the existing release keystore and `android/key.properties`; never generate replacements for this repair.

## Cloud changes

`node tool/repair_android_release.cjs C:\Projects` reads configuration. Add `--apply` to repair it. `--verify-signatures` performs local identity/key-resolution and APK signature checks without cloud calls.

The tool is scoped to project `alpha-ride-29708` / `486103357366` and the two known Android app IDs. It:

- Verifies each existing APK against the release SHA-1 and SHA-256 before cloud changes.
- Checks both `google-services.json` and Dart Android Firebase identities.
- Enables required API Keys, Firebase Management, App Check, Play Integrity and Maps Android services when disabled.
- Adds missing release certificate hashes to Firebase without removing existing hashes.
- Configures off-Play App Check: allow unrecognized app versions, do not require Play licensing, require device integrity. Existing token TTL and backend enforcement remain unchanged.
- Locates configured Maps and Firebase keys without printing them, and adds the package/release SHA-1 pair to existing Android restrictions using an etag. Other applications, certificates and API service restrictions remain intact.
- Refuses to replace browser/server/iOS restrictions or modify another project's keys. It also stops if the Maps API is excluded by the key's service restrictions; add Maps SDK for Android to that key's allowed APIs in Google Cloud Credentials.
- Stores previous configuration (no key strings or access tokens) under the user's `Alpha-Release-Config-Backups` folder.

The process stops on failures, including permission errors. Some changes may already have completed; rerunning reads current state and does not duplicate certificate entries. Active billing, valid API quotas, a certified device and actual successful device attestation are **not proven** by this tool. An owner must resolve any remaining console-side issue. This does not turn off App Check or grant broad IAM permissions.

## Deployment and validation

The passenger first-letter search change requires deploying `passengerSearchPlaces`; shipping the APK alone is insufficient. The script deploys only that changed function. It never requests a paid OTP or sends APKs to anyone.

New APKs use the same signing certificate and can update the previously installed release versions. Do not uninstall just to collect diagnostics. Each app shows a safe support reference (`AC-REJECTED`, `AC-WAIT`, `AC-NETWORK`, `AC-PROVIDER` or `AC-BACKEND`) if verification fails; the tester can send a screenshot without ADB or debug tokens.

Test passenger OTP request and confirmation, driver OTP with a separate number, driver map tiles, first-letter suggestions, map pin confirmation during a slow address lookup, and preservation of existing Firebase profile information. Record the device model and whether the delay is typing/animation lag or a network spinner. This patch does not establish measured performance for every screen.

References:
- https://firebase.google.com/docs/app-check/android/play-integrity-provider
- https://firebase.google.com/docs/reference/appcheck/rest/v1/projects.apps.playIntegrityConfig
- https://developers.google.com/maps/documentation/android-sdk/start
- https://docs.cloud.google.com/api-keys/docs/reference/rest/v2/projects.locations.keys/patch
