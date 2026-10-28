# Location search and driver connection recovery

The October 28 screenshots show a failed passenger Places search, not missing
driver map tiles. Map SDK authorization and Places web-service authorization are
separate. No live Google API settings or device delivery have been verified by CI.

## Release

In PowerShell, update and deploy the Places functions from the passenger/backend
repository. Do not create a new secret version unless changing the actual key.

```powershell
& {
    Set-Location "C:\Projects\Alpha"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Passenger pull failed." }
    npm --prefix functions ci
    if ($LASTEXITCODE -ne 0) { throw "Dependency install failed." }
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
    firebase deploy --project alpha-ride-29708 --only "functions:passengerSearchPlaces,functions:passengerGetPlace"
    if ($LASTEXITCODE -ne 0) { throw "Places deployment failed." }
    flutter build apk --profile
    if ($LASTEXITCODE -ne 0) { throw "Passenger build failed." }
    Set-Location "C:\Projects\alpha_plus"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Driver pull failed." }
    flutter build apk --profile
    if ($LASTEXITCODE -ne 0) { throw "Driver build failed." }
}
```

Install both newly built `build\app\outputs\flutter-apk\app-profile.apk` files.
Building does not update installed apps. Preserve the existing signing keys and
local driver Maps SDK key configuration.

## Places diagnostics

After reproducing search failure on the new build, run:

```powershell
Set-Location "C:\Projects\Alpha"
firebase functions:log --project alpha-ride-29708 --only "passengerSearchPlaces,passengerGetPlace"
```

Look for `passenger_places_provider_failure` with `httpStatus`, `providerStatus`
and `reason`. These structured diagnostics do not include the API key, query,
phone number, provider message or full provider body.

- `SERVICE_DISABLED`: enable Places API (New) in the key's Google Cloud project.
- `BILLING_DISABLED`: correct billing in that project.
- `API_KEY_SERVICE_BLOCKED`: authorize Places API (New) for the server key.
- Android, iOS, referrer or IP restriction errors: use a correctly restricted
  server key. Do not loosen the native Maps SDK key to make server calls work.
- Missing callable / missing secret: finish deployment and bind
  `GOOGLE_PLACES_API_KEY` to both Places functions.
- Account permission errors: inspect the passenger account's role and deletion
  state; do not bypass role checks.

Do not post secret values. A destination may be chosen on the map while search
is unavailable. A configuration error is shown as a service problem, rather
than incorrectly claiming that the place does not exist.

## Driver behavior and acceptance

Online startup waits for both the GPS result and secure server preparation,
observing errors from both immediately. Only one transient preflight retry is
allowed. The switch may be cancelled during startup. A slow operation is no
longer cancelled by an unrelated 20-second UI timeout.

The driver must receive server acknowledgement before the card reports LIVE.
Temporary disconnects retain online intent and show Reconnecting; reconnect and
heartbeat recovery republish without requiring an off/on toggle. Explicitly
going offline cancels the intent before waiting for network cleanup. Delayed
older responses and ownership-checked cleanup cannot reactivate that attempt or
delete a newer presence. The availability cache is scoped to the driver UID.

Wallet eligibility is unchanged: a low positive balance is a warning, while an
empty or suspended wallet must still prevent work. These are not network errors.

On real phones test: (1) place search and selection, (2) online startup on a slow
connection, (3) disconnect and reconnect without touching the switch, (4) cancel
startup then reconnect, (5) finish a ride and receive the next request, and (6)
read the complete status at normal and enlarged accessibility text sizes.
Live credentials, network coverage and actual request delivery need these
device checks in addition to automated tests.
