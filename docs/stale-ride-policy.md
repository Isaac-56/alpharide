# Stale active ride recovery

AlphaRide automatically closes assigned rides that receive no lifecycle update
for 24 hours. This covers rides left in `accepted`, `driver_arriving`, `arrived`,
or `in_progress` after an interrupted test, device loss, or abandoned trip.

The `expireStaleActiveRides` scheduled function runs every five minutes and:

- rechecks the ride inside a Firestore transaction;
- changes the ride to `cancelled` with the `inactive_ride_timeout` audit code;
- removes matching passenger and driver active-ride pointers;
- removes the matching Realtime Database driver assignment;
- stops any open waiting interval without calculating a completion charge.

A stale ride is never completed automatically. It does not create a receipt,
increase ride totals, or debit the driver's prepaid wallet.

Deploy the function with:

```powershell
firebase deploy --only "functions:expireStaleActiveRides"
```
