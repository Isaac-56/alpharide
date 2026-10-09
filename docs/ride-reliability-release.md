# Ride reliability release

Ship the backend before the updated passenger and driver apps. GitHub changes do not deploy Firebase or replace installed APKs.

## Firebase

From alpharide with an authorized Firebase CLI session:

```sh
cd functions
npm ci
npm run check
npm test
cd ..
firebase deploy --project alpha-ride-29708 --only firestore:indexes
firebase deploy --project alpha-ride-29708 --only functions,hosting
```

Retain existing project indexes during deployment; decline removal of indexes maintained outside this file. Wait for the ride_receipts service/date and aggregation indexes to finish building before using service filters. adminGetCommissionDetails is admin-claim protected, uses Juba dates (UTC+2), exact filtered aggregate totals and 100-trip pagination. Search applies to loaded trips; Load more expands those results. New receipts freeze the car/driver summary; older receipts explicitly label the fallback as current profile information.

releaseFinishedDriverPresence retries terminal ride cleanup if the callable's RTDB update fails. It only clears a matching ride ID and preserves the driver's online/offline choice.

Driver photos still require an approved driver_photo_checks photo and the existing short-lived signed URL permission. Passenger photos come from users/{passengerId} when the request is accepted. Missing uploads/approval remain a fallback avatar; licence images are never used as portraits.

## Cross-device verification

Use two signed-in phones with different passenger/driver accounts. Verify a fresh install displays Maps, the approved driver can go online, accepts a request once even after a lost response, and both profile photos load. Cancel before pickup and verify both apps exit the trip and the driver is immediately eligible again. Complete shorter and longer trips: verify final fare, waiting charge, commission, receipt and availability on the passenger phone. Retry a completion to confirm there is only one wallet debit/receipt. Switch the driver offline before cleanup and verify it stays offline.

On Admin, filter a single Juba day and Standard; compare displayed totals against the receipts. Check car plate/driver/route/final fare/fee/earnings, pagination beyond 100 results, empty results and invalid date ranges. Firebase Emulator/integration and real-device verification are required before treating performance and Maps issues as resolved in production.
