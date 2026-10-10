"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildRideOfferMessage,
  validatePushToken,
} = require("../notification_logic");

test("driver notification tokens are trimmed and validated", () => {
  const token = "driver-token-that-is-long-enough";
  assert.equal(validatePushToken(`  ${token}  `), token);
  assert.throws(() => validatePushToken("short"), RangeError);
});

test("Boda offers create an urgent data and display notification", () => {
  const message = buildRideOfferMessage({
    token: "driver-token-that-is-long-enough",
    rideId: "ride-123",
    rideOptionId: "boda",
    pickupAddress: "Juba Town",
    estimatedFare: 12500,
    currencyCode: "SSP",
  });

  assert.equal(message.notification.title, "New Boda ride request");
  assert.equal(message.data.rideId, "ride-123");
  assert.equal(message.android.priority, "high");
  assert.equal(message.android.notification.sound, "default");
});
