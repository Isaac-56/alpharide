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

const { buildUpdateMessage, passengerRideUpdate } = require("../notification_logic");

test("news and discounts use the normal sound channel, ride updates the urgent channel", () => {
  for (const type of ["news", "discount", "ride_update"]) {
    const message = buildUpdateMessage({ token: "passenger-token-that-is-long-enough",
      eventId: "unique-event", title: "Update", body: "Details", type });
    assert.equal(message.android.notification.sound, "default");
    assert.equal(message.apns.payload.aps.sound, "default");
    assert.equal(message.android.notification.channelId,
      type === "ride_update" ? "alpha_ride_alerts_v1" : "alpha_updates_v1");
    assert.equal(message.data.eventId, "unique-event");
  }
});

test("only meaningful passenger status changes alert, live fare writes do not", () => {
  for (const status of ["accepted", "arrived", "in_progress", "completed", "cancelled"]) {
    assert.equal(passengerRideUpdate({ status: "offered" }, { status }).type, "ride_update");
    assert.equal(passengerRideUpdate({ status }, { status, liveDistanceFare: 1200 }), null);
  }
  assert.equal(passengerRideUpdate({ status: "requested" }, { status: "offered" }), null);
  assert.equal(passengerRideUpdate(null, { status: "accepted" }), null);
});
