"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  STALE_ACTIVE_RIDE_TIMEOUT_MS,
  isStaleActiveRide,
  resolveCompletedRideFare,
  resolveDriverRideLock,
  resolveWaitingInterval,
  resolveTrackedRideProgress,
  validateDriverRideTransition,
} = require("../lifecycle_logic");

test("assigned rides expire after 24 hours without lifecycle activity", () => {
  const nowMillis = 1_800_000_000_000;

  for (const status of [
    "accepted",
    "driver_arriving",
    "arrived",
    "in_progress",
  ]) {
    assert.equal(
      isStaleActiveRide({
        status,
        updatedAtMillis: nowMillis - STALE_ACTIVE_RIDE_TIMEOUT_MS,
        nowMillis,
      }),
      true,
    );
  }
});

test("recent and terminal rides never expire as stale active rides", () => {
  const nowMillis = 1_800_000_000_000;

  assert.equal(
    isStaleActiveRide({
      status: "in_progress",
      updatedAtMillis: nowMillis - STALE_ACTIVE_RIDE_TIMEOUT_MS + 1,
      nowMillis,
    }),
    false,
  );
  for (const status of ["requested", "offered", "completed", "cancelled"]) {
    assert.equal(
      isStaleActiveRide({
        status,
        updatedAtMillis: nowMillis - STALE_ACTIVE_RIDE_TIMEOUT_MS * 3,
        nowMillis,
      }),
      false,
    );
  }
});

test("rides with missing or future activity timestamps stay untouched", () => {
  const nowMillis = 1_800_000_000_000;

  assert.equal(
    isStaleActiveRide({
      status: "in_progress",
      updatedAtMillis: null,
      nowMillis,
    }),
    false,
  );
  assert.equal(
    isStaleActiveRide({
      status: "in_progress",
      updatedAtMillis: nowMillis + 1,
      nowMillis,
    }),
    false,
  );
});

test("driver availability preserves only a current assigned ride lock", () => {
  const nowMillis = 1_800_000_000_000;

  assert.equal(resolveDriverRideLock({
    status: "in_progress",
    assignedDriverId: "driver-1",
    driverId: "driver-1",
    updatedAtMillis: nowMillis - 1000,
    nowMillis,
  }), "active");
  assert.equal(resolveDriverRideLock({
    status: "in_progress",
    assignedDriverId: "driver-1",
    driverId: "driver-1",
    updatedAtMillis: null,
    nowMillis,
  }), "active");
});

test("driver availability releases terminal, foreign and stale ride locks", () => {
  const nowMillis = 1_800_000_000_000;

  assert.equal(resolveDriverRideLock({
    status: "completed",
    assignedDriverId: "driver-1",
    driverId: "driver-1",
    updatedAtMillis: nowMillis - 1000,
    nowMillis,
  }), "release");
  assert.equal(resolveDriverRideLock({
    status: "in_progress",
    assignedDriverId: "driver-2",
    driverId: "driver-1",
    updatedAtMillis: nowMillis - 1000,
    nowMillis,
  }), "release");
  assert.equal(resolveDriverRideLock({
    status: "in_progress",
    assignedDriverId: "driver-1",
    driverId: "driver-1",
    updatedAtMillis: nowMillis - STALE_ACTIVE_RIDE_TIMEOUT_MS,
    nowMillis,
  }), "stale");
});

test("driver ride lifecycle advances in the required order", () => {
  assert.deepEqual(
    validateDriverRideTransition("accepted", "driver_arriving"),
    {
      status: "driver_arriving",
      timestampField: "driverArrivingAt",
      completed: false,
    },
  );
  assert.equal(
    validateDriverRideTransition("driver_arriving", "arrived").status,
    "arrived",
  );
  assert.equal(
    validateDriverRideTransition("arrived", "in_progress").status,
    "in_progress",
  );
  assert.equal(
    validateDriverRideTransition("in_progress", "completed").completed,
    true,
  );
});

test("driver ride lifecycle rejects skipped and backwards states", () => {
  assert.throws(
    () => validateDriverRideTransition("accepted", "arrived"),
    /cannot transition/,
  );
  assert.throws(
    () => validateDriverRideTransition("arrived", "driver_arriving"),
    /cannot transition/,
  );
  assert.throws(
    () => validateDriverRideTransition("completed", "in_progress"),
    /cannot transition/,
  );
});

test("passenger and dispatch statuses cannot be submitted by drivers", () => {
  assert.throws(
    () => validateDriverRideTransition("accepted", "cancelled"),
    /not a driver lifecycle transition/,
  );
  assert.throws(
    () => validateDriverRideTransition("accepted", "offered"),
    /not a driver lifecycle transition/,
  );
});

test("completed launch rides persist the trusted server-quoted fare", () => {
  assert.equal(
    resolveCompletedRideFare({ estimatedFare: 12500, finalFare: null }),
    12500,
  );
  assert.equal(
    resolveCompletedRideFare({
      estimatedFare: 12500,
      finalFare: null,
      waitingCharge: 600,
    }),
    13100,
  );
  assert.equal(
    resolveCompletedRideFare({ estimatedFare: 12500, finalFare: 13000 }),
    13000,
  );
});

test("early completion uses tracked distance and the frozen fare policy", () => {
  assert.equal(
    resolveCompletedRideFare({
      estimatedFare: 100000,
      finalFare: null,
      waitingCharge: 200,
      rideOptionId: "standard",
      actualDistanceMeters: 2500,
      farePolicy: {
        minimumFare: 10000,
        baseFare: 10000,
        perKilometer: 9000,
        waitingPerMinute: 100,
      },
    }),
    32700,
  );
});

test("trip odometer accepts movement but rejects drift and GPS jumps", () => {
  const first = { latitude: 4.85, longitude: 31.58, accuracy: 8 };
  const moved = resolveTrackedRideProgress({
    previousPoint: first,
    previousAtMillis: 0,
    nextPoint: { latitude: 4.8501, longitude: 31.58, accuracy: 8 },
    nowMillis: 10000,
    trackedDistanceMeters: 100,
  });
  assert.ok(moved.trackedDistanceMeters > 105);

  const jump = resolveTrackedRideProgress({
    previousPoint: moved.point,
    previousAtMillis: 10000,
    nextPoint: { latitude: 5.85, longitude: 31.58, accuracy: 8 },
    nowMillis: 20000,
    trackedDistanceMeters: moved.trackedDistanceMeters,
  });
  assert.equal(jump.trackedDistanceMeters, moved.trackedDistanceMeters);
});

test("explicit customer waiting is billable from the first minute", () => {
  assert.deepEqual(
    resolveWaitingInterval({
      rideOptionId: "standard",
      waitingSeconds: 75,
      billableWaitingSeconds: 0,
      waitingStartedAtMillis: 1000,
      nowMillis: 182000,
      waitingRatePerMinute: 100,
    }),
    {
      intervalSeconds: 181,
      intervalBillableSeconds: 181,
      waitingSeconds: 256,
      billableWaitingSeconds: 181,
      waitingCharge: 400,
    },
  );
});

test("waiting intervals preserve the rate quoted when the ride was created", () => {
  assert.equal(
    resolveWaitingInterval({
      rideOptionId: "standard",
      waitingStartedAtMillis: 0,
      nowMillis: 180000,
      waitingRatePerMinute: 300,
    }).waitingCharge,
    900,
  );
});

test("completed rides reject missing or invalid trusted fares", () => {
  assert.throws(
    () => resolveCompletedRideFare({ estimatedFare: null, finalFare: null }),
    /missing a valid trusted fare/,
  );
  assert.throws(
    () => resolveCompletedRideFare({ estimatedFare: 0, finalFare: null }),
    /missing a valid trusted fare/,
  );
});
