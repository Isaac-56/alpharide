# AlphaRide South Sudan launch economics

Research reviewed on 17 September 2026.

## Local market evidence

- Snap Rides' Juba app listing says riders see a distance-and-time fare before
  booking and currently pay cash directly to the driver. MTN Mobile Money and
  M-Pesa are described as coming later.
- Snap Rides' driver page advertises a 10% platform commission, leaving the
  driver 90% of every fare.
- Shilu ANA advertises an estimated fare before confirmation, nearest-driver
  matching, and support for local East African payment methods.
- The World Bank's South Sudan mobile-money survey describes a substantially
  cash-based economy with strong interest in mobile money, while also noting
  network, accessibility, trust, and agent-coverage barriers.

Sources:

- https://apps.apple.com/il/app/snap-rides-juba/id6786622474
- https://snaprides.app/
- https://shiluana.com/
- https://documents1.worldbank.org/curated/en/460341563539588094/pdf/Mobile-Money-Ecosystem-Survey-in-South-Sudan-Exploring-the-Current-and-Future-Potential-of-Using-Mobile-Money-for-Effective-Humanitarian-and-Development-Cash-Programming-Executive-Summary.pdf

## Launch decision

AlphaRide will launch with the following server-enforced policy:

1. The passenger sees the complete route-based fare before booking.
2. Cash is the only enabled payment method until a real mobile-money provider
   is integrated and reconciled.
3. The driver collects the cash fare at trip completion.
4. Alpha earns a 10% platform commission; the driver retains 90%.
5. Every completed ride atomically records gross fare, Alpha's fee, driver net
   earnings, cash collected, and settlement status.
6. Driver totals are maintained by trusted Cloud Functions. Client apps can
   display these values but cannot create or alter them.

This launch rate matches the clearest public Juba benchmark while producing
platform revenue without imposing the 20-30% commissions common in more mature
ride-hailing markets.

## Settlement boundary

For a cash trip, the driver physically holds the full fare and owes Alpha the
recorded 10% fee. The first release records that liability transparently but
does not automatically suspend drivers for unpaid balances. Balance enforcement
should only be enabled after Alpha has an admin settlement workflow and a
verified way to record cash or mobile-money deposits.
