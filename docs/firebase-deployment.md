# Firebase live-ride deployment

AlphaRide uses Firebase project `alpha-ride-29708` and second-generation callable functions in `africa-south1`.

## Required secret

Do not commit the Google Routes key. Configure it through Firebase Secret Manager:

```bash
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY
```

The key should be restricted to the Google Routes API and to the server-side project where practical.

## Pre-deploy checks

```bash
cd functions
npm ci
npm run check
npm test
cd ..
flutter analyze
flutter test
```

## Deploy

```bash
firebase use alpha-ride-29708
firebase deploy --only firestore:rules,functions
```

## Real-device validation

1. Sign in to AlphaRide on a real Android device.
2. Choose a live launch option: Boda, Rickshaw, or Standard.
3. Use Cash as the payment method.
4. Confirm the ride and verify a new `rides/{rideId}` document is created.
5. Verify the server-computed fare is shown after creation.
6. Complete a cash ride and verify `driver_ride_summaries/{driverId}` records
   one completed ride, the gross fare, Alpha's 10% platform fee, the driver's
   90% net fare, and the unsettled platform-fee balance.
6. Cancel before driver assignment and confirm the ride stores `status=cancelled`, `cancelledBy=passenger`, and `cancellationReason`.
7. Verify `active_passenger_rides/{passengerId}` is removed after cancellation.

Do not enable client writes to trusted ride assignment, final fare, approval, or completion fields.
