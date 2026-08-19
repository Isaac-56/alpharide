# AlphaRide session and privacy setup

This change stores passenger profile data under the authenticated Firebase UID and
allows only that UID to read or write its private Firestore document tree.

## Deploy the Firestore rules

From the project root:

```powershell
firebase use alpha-ride-29708
firebase deploy --only firestore:rules
```

Confirm that the Firebase project shown before deployment is the production
AlphaRide project.

## Test one active device

1. Sign in with the same phone account on phone A.
2. Keep phone A online and open.
3. Sign in with that account on phone B.
4. Phone A should be signed out as soon as it receives the Firestore session
   update.
5. Sign in with two different phone numbers and confirm each account has its own
   profile, saved places, notifications, rides, and wallet history.

This is app-level session enforcement. A modified client or an offline device
cannot be fully revoked from client code alone. Production-grade token
revocation requires a trusted Firebase Admin backend.

## Legacy profile migration

The first successful login checks for an old `users/{phoneNumber}` document.
When found, it copies that profile and the known private subcollections to
`users/{uid}`. Rules temporarily allow the authenticated owner of that phone
number to read the legacy document for this migration.
