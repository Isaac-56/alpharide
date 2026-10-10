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

## Faster startup and continued matching

Returning sessions can load from the matching local Firestore session cache. The live session listener still signs out an installation when the server confirms a newer login. Startup no longer adds a fixed splash delay or repeats an already completed product-role claim. First sign-in and session migrations still require server confirmation.

Dispatch v3 uses up to five eligible drivers per distance-ordered wave, a 30-second response window and a fixed three-minute search deadline. Expired offers move to untried drivers. Explicit rejection is respected for this search. An unanswered driver may receive one repeat after a 60-second cooldown, allowing recovery from a missed notification; each driver receives at most two offers during this search. If nobody is eligible, matching rechecks every ten seconds when prompted by the foreground passenger screen (eight-second polling, one request in flight). The existing one-minute server worker provides recovery while the app is backgrounded. It can take up to the next worker interval to advance a background search; this is not a continuous background socket.

Every wave checks fresh online location within the existing 12 km radius, approved vehicle class, no active ride, and wallet credit covering the commission. Wallet filtering happens before selecting five drivers. Verification reads work outward in batches of 25, so a fleet of ineligible nearby drivers does not exclude further eligible drivers. Transaction leases prevent duplicate waves, and the final transaction checks that a concurrent cancellation or acceptance has not ended matching. Only one driver can win the existing acceptance transaction.

A Firebase Auth test number does not automatically create an eligible Boda driver. Verify its `drivers/{uid}` approval and Boda registration, wallet credit, online location and driver app connection. `dispatchExclusionCounts` on the ride records busy, profile/vehicle and wallet exclusions; a blank online presence produces no candidates. No sample account bypass is added.

Deploy the new index first (retain existing cloud indexes if asked about deletion):

```powershell
Set-Location "C:\Projects\Alpha"
git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
firebase deploy --project alpha-ride-29708 --only "firestore:indexes"
```

Wait for the `rides` status / offerExpiresAt index to finish building, then deploy the matching entry points:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
firebase deploy --project alpha-ride-29708 --only "functions:createRide,functions:customerServiceCreateRide,functions:retryRideDispatch,functions:rejectRideOffer,functions:expireRideOffers"
```

Rebuild and reinstall both APKs for the startup changes and the passenger polling. Test cold and returning launches, an initial Boda request, rejection, 30-second timeout with another driver available, a driver coming online during search, concurrent accepts, cancellation during a wave, and three-minute search expiry. No live latency or sample-account status has been verified by the automated tests.

Matching design reference: https://www.uber.com/us/en/marketplace/matching/ explains nearby batching and why traffic-aware arrival time can outperform pure distance. Alpha currently has reliable pickup coordinates, so v3 uses straight-line distance as a proxy; it does not claim traffic-aware dispatch.
