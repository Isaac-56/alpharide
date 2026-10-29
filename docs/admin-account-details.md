# Admin account details

Drivers and passengers both open through **View details**. Deletion belongs to the selected account's detail view and still requires complete phone confirmation. It does not bypass active-ride, wallet or administrator checks.

Driver details include identity, phone verification, registration/review dates, vehicle information, licence information and images, identity selfie, wallet controls and transaction history. The existing private driver document endpoint remains in use. Passenger details include the saved profile photo, canonical verified phone, name, email, emergency contact, referral code, registration/update/sign-in dates and ride reference. Missing information is shown explicitly. The current apps do not collect passenger passports or driver passport/car-photo uploads; this update does not invent documents or introduce a new onboarding requirement.

Passenger photos are fetched through an admin-only callable, not public download links. The server resolves the selected profile, checks UID ownership (or a verified legacy phone photo), limits image size and content type, and pins the object generation. Arbitrary URLs, other buckets and other accounts' photo paths are rejected. Closing details or selecting another account discards late responses and releases local photo URLs.

## Deploy in PowerShell

```powershell
& {
    Set-Location "C:\Projects\Alpha"
    git -c gc.auto=0 -c maintenance.auto=false pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "Pull failed. Stop here." }
    npm --prefix functions ci
    if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed." }
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
    firebase deploy --project alpha-ride-29708 --only "functions:adminGetPassengerDetails,functions:adminGetPassengerPhoto,hosting"
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }
}
```

The previously deployed account-deletion and driver-document functions remain required. No mobile APK rebuild is needed. After deployment, hard-refresh the admin panel. Review both roles, open existing photos at full size, switch between accounts while loading, and confirm deletion remains inside details. Use only a disposable account for a deletion/re-registration test.
