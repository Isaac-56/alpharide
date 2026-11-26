# Responsiveness review: November 26, 2026

This change reduces avoidable UI-thread work and decoded image memory. It does not claim measured frame rates on a physical device.

## Changes

- Show a lightweight first frame before Firebase, App Check provider activation and preferences finish. Create authenticated application widgets only after initialization completes. Retry failures without duplicating the Firebase app.
- Bound remote ride avatar decoding to 256 pixels and retain only four recent providers. Bound profile and document preview decoding without resizing uploaded originals.
- Keep one waiting-display timer per widget; stop it when TickerMode is disabled or the app is in the background. Resume from wall-clock time; billing calculations and server authority are unchanged.
- Passenger: isolate live-driver marker animation rebuilds to the Google Map subtree rather than rebuilding the ride card and controls at every animation tick.
- Driver: keep permission reads across rebuilds, refresh after returning from system settings, read document dimensions without a full-resolution bitmap, and run document pixel measurement in a background isolate on Android/iOS.

## Reviewed existing paths

Startup and authentication/session gates, booking/search/map selection, route/fare display, ride offer/active/waiting/completion, history/wallet, profile/settings, and driver registration/document previews were reviewed. Existing request-in-flight guards, stable session/ride streams, paged/builder history lists, and the driver's lazy retained tab stack remain in place. There is no artificial delay added to navigation. Route/fare accuracy, account-role restrictions and backend App Check enforcement are preserved. No minimum backend instances or new service charges are introduced.

## Verification

Regression coverage checks initialization/retry/disposal, no protected content before readiness, timer pause/resume and deadline stability, and bounded/reused photo providers. Driver tests also exercise permission refresh and send the actual pixel-worker payload through compute. Run the full Flutter analyze/test/build pipeline for each repository.

Physical-device acceptance still matters: use a release build for end-to-end behavior and a profile build for frame timing. On an older supported Android phone, walk login, registration, map search, back/forward, quote, ride selection, waiting, history, settings and photo submission; repeat after background/resume. Record UI/raster frame times, memory and network waits separately. A slow server response or Google Maps tile delivery is not a measured UI frame regression; these changes do not guarantee all external requests finish instantly.
