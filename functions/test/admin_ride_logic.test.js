"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeAdminCancellationReason,
  projectLiveRideFare,
} = require("../admin_ride_logic");

test("admin live fare uses tracked distance and active waiting", () => {
  const result = projectLiveRideFare({
    status: "in_progress",
    rideOptionId: "standard",
    estimatedFare: 100000,
    trackedDistanceMeters: 2500,
    farePolicy: {
      minimumFare: 10000,
      baseFare: 10000,
      perKilometer: 9000,
      waitingPerMinute: 100,
    },
    waitingCharge: 100,
    waitingSeconds: 60,
    billableWaitingSeconds: 60,
    isWaiting: true,
    waitingStartedAtMillis: 1000,
    waitingGraceSeconds: 0,
    waitingRatePerMinute: 100,
    nowMillis: 61000,
  });

  assert.equal(result.currentFare, 32700);
  assert.equal(result.waitingCharge, 200);
  assert.equal(result.trackedDistanceMeters, 2500);
  assert.equal(result.isLiveMeteredFare, true);
});

test("non-started rides keep the quoted fare", () => {
  const result = projectLiveRideFare({
    status: "accepted",
    rideOptionId: "boda",
    estimatedFare: 37500,
    trackedDistanceMeters: 0,
  });
  assert.equal(result.currentFare, 37500);
  assert.equal(result.isLiveMeteredFare, false);
});

test("admin-cancelled rides preserve the fare recorded at cancellation", () => {
  const result = projectLiveRideFare({
    status: "cancelled",
    rideOptionId: "standard",
    estimatedFare: 80000,
    fareAtCancellation: 35200,
  });
  assert.equal(result.currentFare, 35200);
});

test("admin cancellation reasons are normalized and validated", () => {
  assert.equal(
    normalizeAdminCancellationReason("  Phone   unavailable  "),
    "Phone unavailable",
  );
  assert.throws(() => normalizeAdminCancellationReason("no"), /5 to 240/);
});
