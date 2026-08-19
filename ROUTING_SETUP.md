# AlphaRide routing setup

The Google Routes key is intentionally not committed to GitHub.

## One-time setup

From the project root in the VS Code PowerShell terminal:

```powershell
.	oolconfigure_routes.ps1
```

Paste the restricted Routes API key when the prompt is waiting for input. The script creates the ignored local file `config/routes.json`.

## Run from VS Code

Open **Run and Debug**, select **AlphaRide (Android with routing)**, then press **F5**.

Or run:

```powershell
.	oolun_android.ps1
```

## Release build

Update `GOOGLE_ANDROID_CERT_SHA1` in `config/routes.json` to the release certificate SHA-1, then run:

```powershell
.	ooluild_android.ps1
```

Never commit `config/routes.json` or paste the API key into Dart source.
