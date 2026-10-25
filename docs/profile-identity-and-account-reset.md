# Profile identity and admin account reset

Passenger profiles refresh from a retained Firestore subscription. Avatar uploads use a new UID-owned Storage path and persist `photoStoragePath`. The drawer and personal-information page read photos with authenticated Storage requests, so an expired download URL is not required. The driver profile header receives its verified phone and displays its own uploaded selfie (including while under review). Only approved driver selfies are shared with matched passengers. Assigned-photo functions verify the viewer, active ride, bucket and owner path before returning bounded image bytes. Driver passenger-photo requests retry transient failures.

The admin passenger list and driver account controls offer **Delete account** with exact phone confirmation. `adminDeleteAccount` requires an admin claim, excludes staff/self deletion and blocks live rides or an unsettled driver wallet. It disables/revokes/deletes Firebase Auth, removes private records/subcollections, tokens, uploaded documents/photos and RTDB driver presence, then releases the phone registration index. Historical rides, receipts, wallet transactions and audit records are retained. A UID tombstone prevents old tokens recreating a profile; a new Auth UID may register the phone. No production account is deleted by deployment.

Cleanup is resumable. The profile root remains listed until the final transaction commits; an interrupted job shows **Retry deletion**. Retry the same selected account and phone. Completed retries are no-ops and cannot erase a fresh registration. Storage and database rules plus ride, role and push registration transactions enforce the deletion fence.

## Deploy from PowerShell

Run each block with its error checks. Do not deploy if the pull fails.

```powershell
& {
    Set-Location "C:\Projects\Alpha"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Passenger pull failed. Stop here." }
    npm --prefix functions ci
    if ($LASTEXITCODE -ne 0) { throw "Backend install failed. Stop here." }
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
    firebase deploy --project alpha-ride-29708 --only "functions:adminDeleteAccount,functions:adminListPassengers,functions:createRide,functions:acceptRideOffer,functions:getAssignedDriverPhoto,functions:getAssignedPassengerPhoto,functions:claimAccountRole,functions:checkAccountRole,functions:registerDriverPushToken,functions:registerPassengerPushToken,firestore:rules,storage,database,hosting"
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed. Stop here." }
    flutter build apk --profile
    if ($LASTEXITCODE -ne 0) { throw "Passenger build failed. Stop here." }
    Set-Location "C:\Projects\alpha_plus"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Driver pull failed. Stop here." }
    flutter build apk --profile
    if ($LASTEXITCODE -ne 0) { throw "Driver build failed. Stop here." }
}
```

The first Storage rules deployment using Firestore lookups may ask to enable the Storage-to-Firestore permission. Enable it; it lets the rules reject deleted accounts. Deploy all listed rules and functions together before using the new APKs. Outputs are `build/app/outputs/flutter-apk/app-profile.apk` in each repository. Refresh the admin panel after deployment.

## Device acceptance check

1. Use two test accounts. Change the passenger photo, save it and confirm both the personal page and drawer show it immediately. Restart the app and confirm its verified phone/photo persist.
2. Confirm the driver profile shows its verified phone and submitted selfie. After approval and ride acceptance, confirm the passenger sees that driver selfie and the driver sees the passenger's current photo. Test all vehicle categories (the same identity flow is shared).
3. Finish/cancel the test ride and settle the driver's test wallet. In admin, delete a disposable test account with the complete phone confirmation. Confirm the old login/profile/documents are gone and the phone can complete fresh OTP registration.
4. An active ride or nonzero wallet must prevent deletion; a different phone or nonadmin caller must also fail. Do not use a real customer as a deletion test.

Automated tests cover storage photo ownership, both matched-photo directions, old-token role reclaim, fresh-UID signup, cleanup/retry behavior, preserved finance history, staff/self/active-ride/wallet protection, avatar path refresh and driver phone rendering. Physical-device and production IAM checks are separate from CI.
