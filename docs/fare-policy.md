# AlphaRide Juba fare policy

## Customer pricing

- A fare appears only after pickup and destination produce a valid road route.
- Normal traffic, red lights and congestion do not create a waiting charge.
- During an active trip, a driver may start **Customer waiting** only when the
  passenger asks the driver to stop.
- Explicit customer waiting is charged proportionally from the first recorded
  minute and rounded up to the nearest 100 SSP.

## Approved rates

| Service | Flag-down | Distance | Customer waiting |
| --- | ---: | ---: | ---: |
| Alpha Boda | 0 SSP | 3,750 SSP/km | 100 SSP/min |
| Alpha Rickshaw | 0 SSP | 5,000 SSP/km | 100 SSP/min |
| Alpha Standard car | 10,000 SSP | 9,000 SSP/km | 100 SSP/min |

Road-distance fares are rounded up to the nearest 500 SSP. The Standard flag-down
is also its minimum fare. Boda and Rickshaw have no separate minimum or flag-down
charge; their fare begins with the measured road distance.

## Server authority

The app may display a preview, but `createRide` recalculates the route and fare
on the server. Waiting starts and stops through authenticated Cloud Functions
using server timestamps. Every ride stores the pricing and commission used when
it was created so later policy changes do not alter an active or completed trip.

Only explicit customer-requested stops may be recorded as waiting. Drivers must
not record normal traffic, road controls or congestion as customer waiting.
