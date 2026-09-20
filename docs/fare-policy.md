# AlphaRide Juba launch fare policy

## What customers see

- No price is shown before both pickup and destination produce a valid road
  route.
- The upfront estimate is based on the vehicle's base fare plus the road
  distance returned by the server-side Google Routes integration.
- Normal traffic, red lights, and congestion do not start a separate waiting
  charge.
- During an active trip, a driver may start **Customer waiting** only when the
  passenger requests a stop. Both apps show the running timer.
- Every customer-requested stop has a two-minute free grace period. Billable
  time after the grace period is accumulated proportionally and rounded up to
  the nearest 100 SSP.

## Launch rates

| Service | Minimum | Base | Distance | Customer waiting |
| --- | ---: | ---: | ---: | ---: |
| Alpha Boda | 4,000 SSP | 2,500 SSP | 1,500 SSP/km | 200 SSP/min |
| Alpha Rickshaw | 6,000 SSP | 3,500 SSP | 2,100 SSP/km | 250 SSP/min |
| Alpha Standard | 10,000 SSP | 6,000 SSP | 3,600 SSP/km | 450 SSP/min |

The route quote is rounded up to the nearest 500 SSP. Waiting is rounded up to
the nearest 100 SSP so partial minutes are still charged proportionally.

## Server authority

The client may display a preview, but `createRide` recalculates the road route
and distance fare on the server. Waiting starts and stops through authenticated
callable functions using server timestamps. On completion, the backend closes
any active waiting interval, calculates the final fare, and then applies the
existing 10% Alpha commission and 90% driver net accounting.

## Research basis and local limitation

Publicly verifiable, current Juba competitor tariff tables were not available,
so AlphaRide does not claim that these rates copy a named South Sudan operator.
The policy keeps the previously approved Juba launch rates and adopts common
transparent ride-hailing behavior:

- Uber explains that upfront prices use base, estimated time, and estimated
  distance, and may increase for destination changes, extra stops, or a trip
  that takes much longer than expected:
  <https://help.uber.com/riders/article/how-are-fares-calculated?nodeId=d2d43bbc-f4bb-4882-b8bb-4bd8acf03a9d>
- AlphaRide intentionally narrows that model for launch: distance determines
  the quote, while only an explicit, visible customer-requested stop adds
  waiting. This avoids charging passengers merely because Juba traffic is slow.

Rates should be reviewed against real completed-trip operating costs before a
production rollout. Changes must be made in both the server pricing table and
the passenger catalogue and must include regression tests.