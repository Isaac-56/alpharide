"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  calculateFare,
  calculateWaitingCharge,
  isCancellableBeforePickup,
  parseGoogleDurationSeconds,
  validateCancellationReason,
  validateCreateRideInput,
  farePolicyFor,
} = require("../ride_logic");

test("boda fare matches the AlphaRide formula", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "boda",
      distanceMeters: 10000,
    }),
    37500,
  );
});

test("standard fare matches the AlphaRide formula", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "standard",
      distanceMeters: 10000,
    }),
    100000,
  );
});

test("server fare settings override defaults for future quotes", () => {
  const policy = farePolicyFor({
    faresByRideOption: {
      standard: {
        minimumFare: 15000,
        baseFare: 12000,
        perKilometer: 10000,
        waitingPerMinute: 250,
      },
    },
  }, "standard");
  assert.deepEqual(policy, {
    minimumFare: 15000,
    baseFare: 12000,
    perKilometer: 10000,
    waitingPerMinute: 250,
  });
  assert.equal(calculateFare({
    rideOptionId: "standard",
    distanceMeters: 1000,
    farePolicy: policy,
  }), 22000);
});

test("zero-flag-down services charge only rounded road distance", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "boda",
      distanceMeters: 100,
    }),
    500,
  );
  assert.equal(
    calculateFare({
      rideOptionId: "rickshaw",
      distanceMeters: 10000,
    }),
    50000,
  );
});

test("customer waiting is proportional and rounded to 100 SSP", () => {
  assert.equal(
    calculateWaitingCharge({
      rideOptionId: "standard",
      billableWaitingSeconds: 0,
    }),
    0,
  );
  assert.equal(
    calculateWaitingCharge({
      rideOptionId: "standard",
      billableWaitingSeconds: 30,
    }),
    100,
  );
  assert.equal(
    calculateWaitingCharge({
      rideOptionId: "boda",
      billableWaitingSeconds: 90,
    }),
    200,
  );
});

test("non-live catalogue products cannot create rides", () => {
  assert.throws(
    () =>
      validateCreateRideInput({
        pickup: {
          address: "A",
          latitude: 4.85,
          longitude: 31.58,
        },
        destination: {
          address: "B",
          latitude: 4.86,
          longitude: 31.59,
        },
        rideOptionId: "ev",
        paymentMethod: "cash",
      }),
    /not enabled for live dispatch/,
  );
});

test("digital payment methods stay disabled for launch", () => {
  assert.throws(
    () =>
      validateCreateRideInput({
        pickup: {
          address: "A",
          latitude: 4.85,
          longitude: 31.58,
        },
        destination: {
          address: "B",
          latitude: 4.86,
          longitude: 31.59,
        },
        rideOptionId: "standard",
        paymentMethod: "card",
      }),
    /not enabled for live rides/,
  );
});

test("Google duration strings are parsed", () => {
  assert.equal(parseGoogleDurationSeconds("1200s"), 1200);
  assert.equal(parseGoogleDurationSeconds("1200.5s"), 1200.5);
});

test("passengers can cancel until the trip starts", () => {
  assert.equal(isCancellableBeforePickup("requested"), true);
  assert.equal(isCancellableBeforePickup("offered"), true);
  assert.equal(isCancellableBeforePickup("accepted"), true);
  assert.equal(isCancellableBeforePickup("driver_arriving"), true);
  assert.equal(isCancellableBeforePickup("arrived"), true);
  assert.equal(isCancellableBeforePickup("in_progress"), false);
  assert.equal(isCancellableBeforePickup("completed"), false);
});

test("cancellation reasons are validated and normalized", () => {
  assert.equal(
    validateCancellationReason("  Pickup point is incorrect  "),
    "Pickup point is incorrect",
  );

  assert.throws(
    () => validateCancellationReason("   "),
    /between 1 and 120 characters/,
  );

  assert.throws(
    () => validateCancellationReason("x".repeat(121)),
    /between 1 and 120 characters/,
  );
});
