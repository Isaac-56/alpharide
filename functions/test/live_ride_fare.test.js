"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { runInNewContext } = require("node:vm");
const { normalizeRideProgressPoint, resolveTrackedRideProgress, resolveCompletedRideFare } = require("../lifecycle_logic");
const { calculateFare } = require("../ride_logic");
const { validateRideId } = require("../dispatch_logic");
function harness(option, overrides = {}) {
  class Timestamp {
    constructor(ms) { this.ms = ms; }
    toMillis() { return this.ms; }
    static now() { return new Timestamp(200000); }
  }
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const point = { latitude: 4.85, longitude: 31.6, accuracy: 5 };
  const ride = { driverId: "driver", status: "in_progress", rideOptionId: option,
    estimatedFare: 20000, trackedDistanceMeters: 1200, lastTrackedLocation: point,
    lastTrackedAt: new Timestamp(190000), ...overrides };
  const context = { exports: {}, REGION: "test", Timestamp, HttpsError,
    requireAuthenticatedDriver: r => r.auth.uid, validateRideId, normalizeRideProgressPoint,
    resolveTrackedRideProgress, calculateFare, logger: { error() {} },
    onCall: (_, handler) => handler,
    db: { collection: () => ({ doc: () => ({}) }), runTransaction: async callback => callback({
      get: async () => ({ exists: true, get: key => ride[key] }),
      update: (_, value) => Object.assign(ride, value),
    }) },
  };
  const source = readFileSync(join(__dirname, "../lifecycle_functions.js"), "utf8");
  const progressStart = source.indexOf("function progressFromSnapshot");
  const progressEnd = source.indexOf("exports.recordRideProgress", progressStart);
  const end = source.indexOf("exports.updateRideStatus", progressEnd);
  runInNewContext(source.slice(progressStart, end), context);
  return { ride, record: (uid = "driver") => context.exports.recordRideProgress({ auth: { uid }, data: { rideId: "ride", point } }) };
}
for (const option of ["boda", "standard", "rickshaw", "comfort", "premium"]) {
  test(`${option}: live distance fare matches completion using the same tracked distance`, async () => {
    const h = harness(option);
    await h.record();
    assert.equal(h.ride.liveDistanceFare, resolveCompletedRideFare({
      estimatedFare: 20000, waitingCharge: 0, rideOptionId: option, actualDistanceMeters: 1200,
    }));
  });
}
test("live fare respects the frozen ride policy and supports zero distance", async () => {
  const h = harness("standard", { trackedDistanceMeters: 0,
    farePolicy: { baseFare: 0, perKilometer: 6000, minimumFare: 0 } });
  await h.record();
  assert.equal(h.ride.liveDistanceFare, 0);
  h.ride.trackedDistanceMeters = 1500;
  await h.record();
  assert.equal(h.ride.liveDistanceFare, 9000);
});
test("other drivers and inactive rides cannot update the running fare", async () => {
  const h = harness("boda");
  await assert.rejects(h.record("other"), e => e.code === "permission-denied");
  h.ride.status = "completed";
  await assert.rejects(h.record(), e => e.code === "failed-precondition");
  assert.equal(h.ride.liveDistanceFare, undefined);
});
