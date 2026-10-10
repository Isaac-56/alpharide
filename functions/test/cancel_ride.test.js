"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { runInNewContext } = require("node:vm");
const test = require("node:test");
const { validateRideId } = require("../dispatch_logic");
const { validateCancellationReason, isCancellableBeforePickup } = require("../ride_logic");

// Execute the production callable against a transactional store. External
// cleanup is deliberately unavailable: cancellation must finish at commit.
function harness({ status = "accepted", passengerId = "passenger", driverLock = "ride", passengerLock = "ride" } = {}) {
  const documents = new Map([
    ["rides/ride", { passengerId, status, driverId: "driver", offeredDriverIds: ["driver", "other", "driver"], cancelledAt: "original-time" }],
    ["active_passenger_rides/passenger", { rideId: passengerLock }],
    ["active_driver_rides/driver", { rideId: driverLock }],
  ]);
  let commits = 0;
  let readAfterWrite = false;
  const ref = (path) => ({ path, doc: (id) => ref(`${path}/${id}`), collection: (id) => ref(`${path}/${id}`) });
  const db = {
    collection: ref,
    async runTransaction(callback) {
      const writes = [];
      await callback({
        async get(reference) {
          if (writes.length) readAfterWrite = true;
          const data = documents.get(reference.path);
          return { exists: !!data, get: (key) => data?.[key] };
        },
        set: (reference, data) => writes.push([reference.path, data]),
        update: (reference, data) => writes.push([reference.path, data]),
        delete: (reference) => writes.push([reference.path, null]),
      });
      for (const [path, data] of writes) {
        if (data === null) documents.delete(path);
        else documents.set(path, { ...documents.get(path), ...data });
      }
      commits++;
    },
  };
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const context = {
    exports: {}, REGION: "africa-south1", db, HttpsError,
    onCall: (_, handler) => handler,
    requireAuthenticatedUser: (request) => request.auth.uid,
    validateRideId, validateCancellationReason, isCancellableBeforePickup,
    FieldValue: { serverTimestamp: () => "new-time" },
    offerReference: (driverId, rideId) => ref(`driver_ride_offers/${driverId}/offers/${rideId}`),
    callableError: (error) => error,
    logger: { info() {} },
    markOffers: () => { throw new Error("Unexpected second batch"); },
    clearDriverPresenceBusy: () => { throw new Error("Unexpected presence wait"); },
  };
  const source = readFileSync(join(__dirname, "..", "index.js"), "utf8");
  const start = source.indexOf("exports.cancelRide = onCall(");
  const end = source.indexOf("\nexports.getAssignedDriverPhoto", start);
  assert.ok(start >= 0 && end > start);
  runInNewContext(source.slice(start, end), context);
  return {
    cancel: () => context.exports.cancelRide({ auth: { uid: "passenger" }, data: { rideId: "ride", reason: "Changed my mind" } }),
    documents,
    commits: () => commits,
    readAfterWrite: () => readAfterWrite,
  };
}

test("cancellation atomically closes offers and matching locks without waiting on cleanup", async () => {
  const h = harness();
  const result = await h.cancel();
  assert.equal(result.status, "cancelled");
  assert.equal(h.commits(), 1);
  assert.equal(h.readAfterWrite(), false);
  assert.equal(h.documents.get("rides/ride").cancellationReason, "Changed my mind");
  assert.equal(h.documents.get("driver_ride_offers/driver/offers/ride").status, "cancelled");
  assert.equal(h.documents.get("driver_ride_offers/other/offers/ride").status, "cancelled");
  assert.equal(h.documents.has("active_passenger_rides/passenger"), false);
  assert.equal(h.documents.has("active_driver_rides/driver"), false);
});

test("retrying a cancelled ride preserves settlement time and newer ride locks", async () => {
  const h = harness({ status: "cancelled", driverLock: "new-ride", passengerLock: "new-ride" });
  await h.cancel();
  await h.cancel();
  assert.equal(h.documents.get("rides/ride").cancelledAt, "original-time");
  assert.equal(h.documents.get("active_driver_rides/driver").rideId, "new-ride");
  assert.equal(h.documents.get("active_passenger_rides/passenger").rideId, "new-ride");
});

for (const status of ["in_progress", "completed"]) {
  test(`cancellation rejects ${status} rides without changing offers or locks`, async () => {
    const h = harness({ status });
    await assert.rejects(h.cancel(), { code: "failed-precondition" });
    assert.equal(h.commits(), 0);
    assert.equal(h.documents.get("rides/ride").status, status);
    assert.equal(h.documents.get("active_driver_rides/driver").rideId, "ride");
  });
}

test("another passenger cannot cancel the ride", async () => {
  const h = harness({ passengerId: "someone-else" });
  await assert.rejects(h.cancel(), { code: "permission-denied" });
  assert.equal(h.commits(), 0);
});
