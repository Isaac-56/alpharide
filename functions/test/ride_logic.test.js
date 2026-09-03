"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  calculateFare,
  isCancellableBeforePickup,
  parseGoogleDurationSeconds,
  validateCancellationReason,
  validateCreateRideInput,
} = require("../ride_logic");

test("boda fare matches the AlphaRide formula", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "boda",
      distanceMeters: 10000,
      durationSeconds: 20 * 60,
    }),
    21500,
  );
});

test("standard fare matches the AlphaRide formula", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "standard",
      distanceMeters: 10000,
      durationSeconds: 20 * 60,
    }),
    51000,
  );
});

test("minimum fares are enforced", () => {
  assert.equal(
    calculateFare({
      rideOptionId: "boda",
      distanceMeters: 100,
      durationSeconds: 60,
    }),
    4000,
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
        rideOptionId: "premium",
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

test("only pre-assignment request states cancel in Step 2", () => {
  assert.equal(isCancellableBeforePickup("requested"), true);
  assert.equal(isCancellableBeforePickup("offered"), true);
  assert.equal(isCancellableBeforePickup("accepted"), false);
  assert.equal(isCancellableBeforePickup("in_progress"), false);
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
