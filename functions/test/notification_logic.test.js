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
  assert.equal(message.android.notification.sound, "alpha_luxe");
});

const { buildUpdateMessage, passengerRideUpdate } = require("../notification_logic");

test("news and discounts use the normal sound channel, ride updates the urgent channel", () => {
  for (const type of ["news", "discount", "ride_update"]) {
    const message = buildUpdateMessage({ token: "passenger-token-that-is-long-enough",
      eventId: "unique-event", title: "Update", body: "Details", type });
    assert.equal(message.android.notification.sound, "alpha_luxe");
    assert.equal(message.apns.payload.aps.sound, "alpha_luxe.wav");
    assert.equal(message.android.notification.channelId,
      type === "ride_update" ? "alpha_ride_alerts_luxe_v2" : "alpha_updates_luxe_v2");
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

test("every vehicle category uses the approved Alpha Luxe request sound", () => {
  for (const rideOptionId of ["boda", "rickshaw", "standard", "comfort", "premium"]) {
    const message = buildRideOfferMessage({ token: "driver-token-that-is-long-enough",
      rideId: "ride-test", rideOptionId, pickupAddress: "Pickup", estimatedFare: 1000, currencyCode: "SSP" });
    assert.equal(message.android.notification.sound, "alpha_luxe");
    assert.equal(message.android.notification.channelId, "alpha_ride_alerts_luxe_v2");
    assert.equal(message.apns.payload.aps.sound, "alpha_luxe.wav");
  }
});

test("Android and iOS bundle the same valid, short PCM notification recording", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const root = path.resolve(__dirname, "../..");
  const android = fs.readFileSync(path.join(root, "android/app/src/main/res/raw/alpha_luxe.wav"));
  const ios = fs.readFileSync(path.join(root, "ios/Runner/alpha_luxe.wav"));
  assert.deepEqual(android, ios);
  assert.equal(android.toString("ascii", 0, 4), "RIFF");
  assert.equal(android.toString("ascii", 8, 12), "WAVE");
  assert.equal(android.readUInt16LE(20), 1); // Linear PCM.
  const byteRate = android.readUInt32LE(28);
  const duration = android.readUInt32LE(40) / byteRate;
  assert.ok(duration > 0 && duration < 30);
  assert.ok(android.subarray(44).some((byte) => byte !== 0));
});
