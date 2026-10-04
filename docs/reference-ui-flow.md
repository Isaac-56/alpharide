# AlphaRide reference-style passenger flow

AlphaRide follows a map-first, one-primary-action-per-screen journey while
keeping AlphaRide's neon-green identity and original vehicle artwork.

## Journey

1. Phone number, OTP and profile setup
2. Location permission and map home
3. Pickup and destination search or map selection
4. Expanded ride-class selection with fare status
5. Route and payment confirmation
6. Driver search and assignment
7. Pickup, waiting and in-trip status
8. Completion, receipt and ride history
9. Wallet, saved places, support, settings and profile

## Interaction rules

- Keep the map visible whenever location or live trip context matters.
- Put the current task in a rounded bottom sheet with one dominant action.
- Use at least 48 logical pixels for interactive controls.
- Show progress, loading, retry and cancellation states in-place.
- Use semantic labels and never communicate status by color alone.
- Support the same hierarchy and contrast in light and dark themes.
- Preserve AlphaRide vehicle images for Boda, Rickshaw and car classes.

