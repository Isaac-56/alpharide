# Alpha Dispatch customer-service portal

Alpha Dispatch is a separate, restricted phone-booking portal hosted at:

`https://alpha-ride-29708.web.app/dispatch/`

It is intentionally separate from Alpha Admin. A customer-service account can
search locations, quote and create phone bookings, cancel eligible phone
bookings, and monitor the phone-booking queue. It cannot approve drivers,
change commission, recharge wallets, manage receipts, or use any other admin
operation.

## Booking flow

1. A customer calls Alpha Ride.
2. The operator records the customer's name and callback number.
3. The operator selects the pickup, destination, and ride category.
4. The backend calculates a trusted road distance and fare, creates the ride,
   and sends offers to eligible nearby drivers.
5. An offer is labelled `Phone booking`, without exposing the customer's phone
   number to every candidate.
6. After a driver accepts, the assigned driver can see and copy the customer's
   phone number and is instructed to call on arrival.

The caller does not need a passenger-app account. A one-way hash of the
normalized phone number is used as the private passenger identity for active
ride locking. The raw number is stored on the protected ride so only backend
staff functions and the assigned driver can read it.

## Create a staff login

Create the staff member as an Email/Password user in Firebase Authentication,
then grant only the customer-service claim:

```powershell
cd C:\Projects\Alpha\functions
npm run customer-service:grant -- operator@example.com grant
```

The operator must sign out and sign in again after a claim change. To remove
access:

```powershell
npm run customer-service:grant -- operator@example.com revoke
```

The command uses Application Default Credentials. If needed on an authorized
office computer, run `gcloud auth application-default login` first and revoke
those local credentials after the claim change.

## Google API requirement

`GOOGLE_ROUTES_API_KEY` remains a server-side Firebase secret. Enable both the
Routes API and Places API for the Google Cloud project/key used by that secret.
The browser never receives the secret value.

## Deploy

```powershell
cd C:\Projects\Alpha
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
firebase use alpha-ride-29708
firebase deploy --only "functions,hosting"
Remove-Item Env:FUNCTIONS_DISCOVERY_TIMEOUT -ErrorAction SilentlyContinue
```

Phone-booking actions are recorded in `customer_service_audit`. Ride writes
remain backend-only and the portal accesses Firestore only through authorized
callable functions.
