# Alpha Admin portal

Alpha Admin is the office-only web interface for driver approval and prepaid
wallet management. It is hosted separately from the passenger and driver apps.

## Security model

- Staff sign in with Firebase Authentication email/password accounts.
- An account must also have the custom claim `admin: true`.
- Wallet credit, suspension and driver review actions use callable Cloud
  Functions. The browser cannot write directly to driver wallets.
- Every recharge stores the administrator UID/email, receipt reference,
  before/after balances and timestamp in the driver's wallet ledger.
- Driver apps have read-only access to their own wallet and ledger.
- Never share an administrator account with a driver or place service-account
  credentials in this repository.

## Create the first administrator

1. Create a staff email/password user in Firebase Authentication.
2. Authenticate the Firebase CLI/Application Default Credentials on the trusted
   office computer.
3. From `functions`, run:

   ```powershell
   npm run admin:grant -- admin@example.com grant
   ```

4. Sign out of Alpha Admin and sign in again so the refreshed ID token contains
   the new claim.

To remove access:

```powershell
npm run admin:grant -- admin@example.com revoke
```

## Deploy

From the AlphaRide repository root:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
firebase use alpha-ride-29708
firebase deploy --only "firestore:rules,functions,hosting"
Remove-Item Env:FUNCTIONS_DISCOVERY_TIMEOUT -ErrorAction SilentlyContinue
```

Firebase prints the Hosting URL when deployment completes.

## Office recharge procedure

1. Search for the driver by name, phone or plate.
2. Confirm the driver identity and received payment.
3. Enter the exact SSP amount and a unique receipt/reference.
4. Confirm the recharge and verify the new balance and ledger row.
5. Give the driver the matching receipt.

Do not manually edit `driver_wallets` in the Firebase Console. Use Alpha Admin
so every balance change remains attributable and auditable.

## Wallet enforcement

- Balance must be positive before Alpha Plus can go online.
- The estimated 10% Alpha fee must be covered before a driver receives or
  accepts a ride offer.
- The actual 10% fee is deducted atomically when a ride completes.
- A balance below 20,000 SSP is marked low and shown as a recharge warning.
- Suspended or exhausted wallets cannot work until an administrator resolves
  the account or records a recharge.
