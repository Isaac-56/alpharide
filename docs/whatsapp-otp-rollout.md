# WhatsApp OTP rollout

Status: implementation requires CI and a real-device end-to-end test before
production cutover. A successful dashboard/PowerShell Bird test alone is not an
application login test.

## Bird
Use Verify > Configure > Channels > WhatsApp > Bird Verify (default).
In Destinations allow South Sudan only, WhatsApp only, and remove custom sender
overrides until AlphaRide's business and Authentication template are approved.
Use a dedicated Verify API key for the app backend, not for unrelated OTP flows.
The backend sends only channels=["whatsapp"]; no SMS/email fallback.
Set six-digit codes, 10-minute validity, five attempts, 60-second resend delay.
Bird's API key is the Firebase secret BIRD_API_KEY, already provisioned by the owner.
Never add this key to Flutter, GitHub, or a client configuration file.

## Firebase prerequisites
Both new callables always enforce App Check. Register both Android apps with
Play Integrity in Firebase App Check. Production builds must meet that provider's
requirements. For sideloaded development testing, run each app with:
flutter run --debug --dart-define=ALPHA_APP_CHECK_DEBUG=true
Register that installation's debug token in Firebase Console > App Check >
the matching app > Manage debug tokens. Treat debug tokens as secrets.
Do not disable enforcement to make a test work.

Custom Firebase tokens require the runtime service account to sign tokens.
After deploying, inspect verifyWhatsAppOtp's serviceConfig.serviceAccountEmail
in Cloud Functions or with gcloud functions describe (gen2, africa-south1).
Enable the IAM Service Account Credentials API.
Grant that runtime identity roles/iam.serviceAccountTokenCreator on its own
service-account resource (not on the entire project). If using a different
signing identity, scope the permission to that signer instead.
Retain the runtime's existing Firebase Auth and Firestore permissions.
No downloadable service-account private key is needed.

## Deploy backend first
From C:\Projects\Alpha, on this feature branch:
firebase deploy --project alpha-ride-29708 --only "functions:requestWhatsAppOtp,functions:verifyWhatsAppOtp"

Both functions run in africa-south1 and use the existing BIRD_API_KEY secret.
Existing Firebase SMS endpoints and installed apps remain functional.
There is no data migration: verified phone lookup resolves the existing Firebase
UID. The apps sign in using a custom token, then retain their current role and
single-device session checks. New accounts are created only after OTP success.

whatsapp_auth_challenges is covered by the existing Firestore deny-all catchall.
Clients must never get read/write access to it. Optionally configure Firestore TTL
on deleteAfter for cleanup; expiration is enforced in code even without TTL.
Initial budgets: five send attempts per phone/hour, ten per IP/hour, 500 globally
per day; 30 checks/IP/10 minutes; five code attempts/challenge and 60-second resend
delay. These limits include failed sends. Review intentionally as usage grows.
One record per phone coordinates both apps. A newer request replaces the earlier
challenge. A network-ambiguous check requires a new challenge; custom tokens are
never cached or replayed. Admin deletion/reset during a pending challenge rejects
that login. Recheck account deletion/disabled status before issuing a token.

## Device acceptance tests
1. Returning passenger: same UID, photo, wallet/history and session behavior.
2. Returning driver: same UID, onboarding, vehicle and approval state.
3. New number: correct onboarding, phone recorded, correct role.
4. Wrong app for existing role: rejected by the existing role checks.
5. Wrong/expired code, five failures, rapid resend, concurrent verification.
6. Background WhatsApp/app switch, Copy code/paste, then complete login.
7. Disabled/deleting account cannot log in; reset account needs a fresh challenge.
8. Invalid App Check token is rejected before a paid send.
9. Bird wallet/transport failure: readable error and no accidental login.
10. Confirm actual sender is Bird Verify and last_channel is whatsapp.

Do not log/pass around OTPs, verification handles, custom tokens or API keys.
Do not treat CI as proof of real carrier delivery or Play Integrity readiness.

## Rollback
Reinstall the prior APKs to use the previous Firebase SMS flow.
No old Auth records or phone providers are removed by this change.
When branding is approved, change the sender/template in Bird and repeat the
real send/check test. The client/backend request contract stays the same.
