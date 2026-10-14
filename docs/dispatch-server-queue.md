# Server-owned ride matching

Ride creation still attempts immediate dispatch. The scheduleRideDispatch Firestore
trigger also schedules processRideDispatch tasks at the persisted next due time.
This continues matching if the passenger closes or backgrounds the app. The
one-minute scheduled sweep remains a fallback.

The queue uses deterministic hashed task IDs, retryable enqueue failures, existing
transactional dispatch leases, a fixed search deadline and terminal-state checks.
It does not promise exactly-once FCM delivery or override an offline driver.

Deploy processRideDispatch first so the queue exists, then deploy
scheduleRideDispatch and all functions that import dispatch_retry.js:
createRide, retryRideDispatch, rejectRideOffer, expireRideOffers,
customerServiceCreateRide. Deploy database rules if the latitude index is absent.

The trigger runtime service account needs Cloud Tasks Enqueuer, permission to act
as the task service account, and that task service account needs permission to
invoke the task worker. If deployment or enqueue logs report PERMISSION_DENIED,
inspect the actual runtime service account before granting these specific roles.
Do not expose the task worker for unauthenticated public requests.

Verify live, on the updated driver build:

1. Leave the approved, funded driver online for at least five minutes.
2. Log into the passenger app later and request the matching vehicle category.
3. Background the passenger app while searching; matching must continue.
4. Receive a request with the driver app backgrounded and notification permission
   enabled. Do not force-stop the app.
5. Finish a trip and order again without toggling online.
6. Cancel during matching; no queued task may resurrect the request.

Use scheduleRideDispatch/processRideDispatch logs to verify queue execution and
the "Ride dispatch round finished" log for candidate counts, exclusion reasons and
processing duration. A successful FCM send is provider acceptance, not a device
delivery acknowledgement.

Firestore profile/wallet/lock reads are now bounded to nearest-candidate batches
instead of an up-front lock read for every nearby driver. The RTDB latitude query
still reads a geographic band; large-fleet load testing and finer geographic
partitioning remain necessary before claiming production-scale capacity.
