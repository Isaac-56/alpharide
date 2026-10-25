# Server API keys before exporting APKs

The Android apps must include a Maps SDK display key and public Firebase configuration. A local `secrets.properties` file keeps a display key out of Git, but the build still embeds it in the APK. Protect Maps SDK keys with Android package and signing-certificate restrictions. Firebase configuration keys identify the Firebase project; they are not server credentials.

Route calculation already uses Firebase Functions and `GOOGLE_ROUTES_API_KEY`. Passenger autocomplete and selected-place details now use `passengerSearchPlaces` and `passengerGetPlace` in `africa-south1`, with a separate Secret Manager secret named `GOOGLE_PLACES_API_KEY`. There is no direct Places HTTP request or Places key in the passenger Dart service, and no fallback to a client key. Alpha Plus has no corresponding passenger-search service to migrate.

The new endpoints require an active passenger role, reject accounts being deleted, validate inputs, apply a shared 100-request-per-minute limit per UID, and return only selected public place fields. Two-minute bounded in-memory caches reduce duplicate requests within a search session. Autocomplete and selection share a namespaced billing session; a successful selection starts a fresh client session. UI debounce and stale-response protection remain in place. Limits are private server data and are cleared by admin account deletion.

## One-time cloud configuration

1. In Google Cloud project **alpha-ride-29708**, enable **Places API (New)**.
2. Create a **new server-only key**, restricted to **Places API (New)**. Do not reuse a key shipped in an APK, a public Firebase configuration or Git history. Do not use an Android application restriction on this server key. If static server egress is configured, restrict the key to those IPs.
3. Run the following command and paste the new key into the Firebase CLI's secret-entry prompt. Keep the value out of source code and chat.

```powershell
Set-Location "C:\Projects\Alpha"
firebase functions:secrets:set GOOGLE_PLACES_API_KEY --project alpha-ride-29708
```

4. After installing updated apps on all test devices, remove Places web-service access from the old client key. Keep APIs required by Firebase Authentication and Maps SDK available. Do not delete or rotate the Firebase configuration key as a shortcut. The existing call-centre Places functions still use `GOOGLE_ROUTES_API_KEY`; keep their required server API access until a separate migration.
5. Check Maps SDK Android restrictions for **com.alpharideapp.passengerapp** and **com.alpharide.driver**, using the certificate that signs the APK being shared. A recipient installing the same APK does not need a new key or certificate registration.

## Existing route key

`GOOGLE_ROUTES_API_KEY` is already read only by the server. If its **value** was ever embedded in an old APK, public configuration or Git history, replace it with a fresh server-only key too: moving a previously exposed value into Secret Manager does not revoke the exposed copy. The existing call-centre endpoints also use this secret for Places, so that key needs **Routes API** and **Places API (New)** access.

Only when rotating that existing route secret, update it in the CLI and redeploy every function bound to it:

```powershell
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY --project alpha-ride-29708
firebase deploy --project alpha-ride-29708 --only "functions:calculateRoute,functions:createRide,functions:customerServiceSearchPlaces,functions:customerServiceGetPlace,functions:customerServiceQuoteRide,functions:customerServiceCreateRide"
```

After updated server keys and APKs are working, remove Routes/Places web-service permissions from the public client key while retaining the Firebase and Maps SDK APIs it still uses. This console configuration cannot be verified by source-code tests.

## Deploy, then rebuild

Do not export an old APK before deploying these new endpoints and setting their secret.

```powershell
& {
    Set-Location "C:\Projects\Alpha"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Pull failed. Stop here." }
    npm --prefix functions ci
    if ($LASTEXITCODE -ne 0) { throw "Backend install failed. Stop here." }
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
    firebase deploy --project alpha-ride-29708 --only "functions:passengerSearchPlaces,functions:passengerGetPlace,functions:adminDeleteAccount"
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed. Stop here." }
    flutter build apk --profile
    if ($LASTEXITCODE -ne 0) { throw "Passenger build failed. Stop here." }
}
```

These targets assume the earlier profile-photo/account-deletion deployment has already been completed. If it has not, follow [that deployment guide](profile-identity-and-account-reset.md) too. The driver source is unchanged by this search-key migration. Its Maps display key remains in `android/secrets.properties` at build time.

Before sharing, test signed-in pickup/destination suggestions, selection on the map, and a fare preview. Server-key configuration and live Google API authorization are separate from CI: fake Google responses in tests do not prove a production key is enabled or restricted correctly.

References: [Google Maps API security](https://developers.google.com/maps/api-security-best-practices), [Places sessions](https://developers.google.com/maps/documentation/places/web-service/using-session-tokens), [Firebase API keys](https://firebase.google.com/docs/projects/api-keys).
