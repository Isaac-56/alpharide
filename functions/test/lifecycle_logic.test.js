"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  resolveCompletedRideFare,
  resolveWaitingInterval,
  validateDriverRideTransition,
} = require("../lifecycle_logic");

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

test("waiting intervals apply a fresh two-minute grace period", () => {
  assert.deepEqual(
    resolveWaitingInterval({
      rideOptionId: "standard",
      waitingSeconds: 75,
      billableWaitingSeconds: 0,
      waitingStartedAtMillis: 1000,
      nowMillis: 182000,
      waitingRatePerMinute: 450,
    }),
    {
      intervalSeconds: 181,
      intervalBillableSeconds: 61,
      waitingSeconds: 256,
      billableWaitingSeconds: 61,
      waitingCharge: 500,
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
    300,
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