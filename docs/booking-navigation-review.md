# Booking navigation and responsiveness review

## Back behavior

- Map picker returns to search without selecting a point on cancellation.
- Search returns to its caller without changing the previous destination on cancellation.
- Booking confirmation returns to ride selection with its quote intact.
- Ride details and the payment sheet return to ride selection.
- Home's booking panel has an explicit back button. Back returns to destination search and cancels pending quote updates, preserving a manually selected pickup. Back from that search returns home.
- An expanded panel without a destination collapses before exiting. A manually selected pickup then reverts to current location on Back.
- Only bare home displays “Press back again to exit”. A second press within two seconds exits; a later press starts a new interval.
- Account, wallet, activity, settings and feedback pages retain their existing Navigator stack. The drawer reopens when returning from its pages, and Back closes it first.
- Registration retains its leave-registration flow. An active ride retains its existing cancellation confirmation; Back must not silently cancel a booked ride.

## Responsiveness changes

- Standard is selected before the first vehicle tap. User selection persists while editing the current trip and resets to Standard when the destination is cleared.
- Autocomplete uses a bounded two-minute cache within a search session, coalesces identical pending requests, and displays cached results without another network wait. Different map areas have separate cache keys. Completing place details clears the session cache.
- The search list removes unrelated old suggestions while the new query is pending. First-letter queries and the 200 ms typing debounce remain enabled.
- Passenger home can center on an accurate location less than two minutes old while fresh GPS is obtained. Fresh GPS still runs. Pickup coordinates remain fixed while a destination/quote is selected.
- Autocomplete, place details and calculateRoute scale to zero: no reserved-instance minimum charge. Cold starts can still delay a first request. Route calculation retains concurrent authorization/routing/pricing reads and route caching.
- The release workflow now deploys calculateRoute and passengerGetPlace as well as passengerSearchPlaces, so the route/fare optimizations actually reach Firebase.

## Verification limits

Widget tests cover root back timing, booking-step consumption, child route return and default Standard confirmation. Service tests cover repeated/in-flight search caching. Source review covers the remaining stacks listed above. This is not a physical-device test of every page.

Google map tile delivery, mobile network latency, GPS and provider response times still require a release-device check. No invented fare, straight-line distance fare, or client-only booking approval is introduced to hide a slow route request.
