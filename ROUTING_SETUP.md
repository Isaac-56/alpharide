# AlphaRide server-side routing

AlphaRide route previews and trusted ride quotes are calculated by callable
Cloud Functions in `africa-south1`. The Android app never receives the Google
Routes API key.

## One-time server secret

From the project root, authenticate the Firebase CLI and set the existing
Google Routes API key in Secret Manager:

```powershell
firebase use alpha-ride-29708
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY
```

The key should be restricted to the Routes API and the Firebase/Google Cloud
project. Do not place it in Dart, Android resources, VS Code launch settings,
or a committed configuration file.

## Deploy routing

```powershell
cd functions
npm ci
npm run check
npm test
cd ..
firebase deploy --only "functions:calculateRoute,functions:createRide"
```

`calculateRoute` requires a signed-in Firebase user, validates coordinates,
limits each account to 30 preview requests per minute, and returns only the
encoded route polyline, distance, and duration. `createRide` independently
recalculates the trusted route and fare before storing a ride.

## Run and build

No local route configuration is required:

```powershell
.\tool\run_android.ps1
.\tool\build_android.ps1
```
