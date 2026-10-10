"use strict";
const assert = require("node:assert/strict");
const test = require("node:test");
const { createDispatchEngine, SEARCH_WINDOW_MS } = require("../dispatch_retry");
class Timestamp {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
  static fromMillis(ms) { return new Timestamp(ms); }
}
function harness(count = 1) {
  let now = 100000;
  const docs = new Map([
    ["rides/ride", { status: "requested", passengerId: "passenger", pickup: { latitude: 4.85, longitude: 31.6 }, destination: { latitude: 4.86, longitude: 31.61 }, requiredVehicleType: "boda", rideOptionId: "boda", estimatedFare: 1000, platformCommissionBps: 1000, currencyCode: "SSP", paymentMethod: "cash", requestedAt: Timestamp.fromMillis(now) }],
    ["active_passenger_rides/passenger", { rideId: "ride" }],
  ]);
  const presence = {};
  const sent = [];
  let beforePresence;
  let tail = Promise.resolve();
  let wroteBeforeRead = false;
  const ref = (path) => ({ path, id: path.split("/").at(-1), doc: (id) => ref(`${path}/${id}`), collection: (id) => ref(`${path}/${id}`) });
  const snap = (reference) => {
    const data = docs.get(reference.path);
    return { exists: !!data, get: (key) => data?.[key], data: () => data };
  };
  const db = {
    collection: ref,
    async getAll(...refs) { return refs.map(snap); },
    runTransaction(callback) {
      const run = tail.then(async () => {
        const writes = [];
        const result = await callback({
          async get(reference) { if (writes.length) wroteBeforeRead = true; return snap(reference); },
          update: (reference, value) => writes.push([reference.path, value, true]),
          set: (reference, value, options) => writes.push([reference.path, value, options?.merge]),
          delete: (reference) => writes.push([reference.path, null]),
        });
        for (const [path, value, merge] of writes) {
          if (value === null) docs.delete(path);
          else docs.set(path, merge ? { ...docs.get(path), ...value } : value);
        }
        return result;
      });
      tail = run.catch(() => {});
      return run;
    },
  };
  const engine = createDispatchEngine({
    db, Timestamp, FieldValue: { serverTimestamp: () => Timestamp.fromMillis(now) },
    realtimeDb: { ref: (path) => ({ transaction: async (callback) => {
      const id = path.split("/").at(-1);
      const next = callback(presence[id]);
      if (next === undefined) return { committed: false };
      presence[id] = next;
      return { committed: true, snapshot: { val: () => next } };
    }, get: async () => {
      if (beforePresence) await beforePresence();
      return { exists: () => true, val: () => presence };
    } }) },
    sendPush: async (data) => sent.push(data), logger: { warn() {} }, clock: () => now,
  });
  const addDriver = (id, offset = 0) => {
    presence[id] = { driverId: id, isOnline: true, updatedAt: now, vehicleType: "Boda", latitude: 4.85 + offset, longitude: 31.6 };
    docs.set(`drivers/${id}`, { reviewStatus: "approved", registration: { vehicleType: "Boda" } });
    docs.set(`driver_wallets/${id}`, { balance: 10000 });
  };
  for (let i = 0; i < count; i++) addDriver(`driver${i}`, i / 10000);
  return { docs, sent, presence, db, addDriver,
    dispatch: () => engine.dispatchRide({ rideId: "ride" }),
    advance: (ms) => { now += ms; for (const value of Object.values(presence)) value.updatedAt = now; },
    beforePresence: (fn) => { beforePresence = fn; },
    wroteBeforeRead: () => wroteBeforeRead,
  };
}

test("nearest Boda wave continues to the next eligible drivers after timeout", async () => {
  const h = harness(8);
  assert.equal(await h.dispatch(), "offered");
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver0", "driver1", "driver2", "driver3", "driver4"]);
  h.advance(30001);
  assert.equal(await h.dispatch(), "offered");
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver5", "driver6", "driver7"]);
  assert.equal(h.docs.get("driver_ride_offers/driver0/offers/ride").status, "expired");
  assert.equal(h.wroteBeforeRead(), false);
});

test("wallet filtering happens before the five-driver wave limit", async () => {
  const h = harness(8);
  for (let i = 0; i < 5; i++) h.docs.set(`driver_wallets/driver${i}`, { balance: 0 });
  await h.dispatch();
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver5", "driver6", "driver7"]);
  assert.equal(h.docs.get("rides/ride").dispatchExclusionCounts.wallet, 5);
});

test("a waiting request picks up a driver who comes online later", async () => {
  const h = harness(0);
  assert.equal(await h.dispatch(), "requested");
  h.advance(10001);
  h.addDriver("new-driver");
  assert.equal(await h.dispatch(), "offered");
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["new-driver"]);
});

test("simultaneous workers publish a single wave and a single push", async () => {
  const h = harness(8);
  await Promise.all([h.dispatch(), h.dispatch(), h.dispatch()]);
  assert.equal(h.sent.length, 1);
  assert.equal(h.docs.get("rides/ride").dispatchRound, 1);
});

for (const status of ["cancelled", "accepted"]) {
  test(`a ${status} ride cannot be resurrected during candidate verification`, async () => {
    const h = harness(1);
    h.beforePresence(async () => { h.docs.set("rides/ride", { ...h.docs.get("rides/ride"), status }); });
    assert.equal(await h.dispatch(), status);
    assert.equal(h.docs.get("rides/ride").status, status);
    assert.equal(h.docs.has("driver_ride_offers/driver0/offers/ride"), false);
    assert.equal(h.sent.length, 0);
  });
}

test("search expires at its fixed deadline without deleting a newer passenger lock", async () => {
  const h = harness(0);
  await h.dispatch();
  h.docs.set("active_passenger_rides/passenger", { rideId: "newer" });
  h.advance(SEARCH_WINDOW_MS);
  assert.equal(await h.dispatch(), "expired");
  assert.equal(h.docs.get("active_passenger_rides/passenger").rideId, "newer");
});

test("explicitly rejected drivers are not offered the same search again", async () => {
  const h = harness(3);
  h.docs.get("rides/ride").rejectedDriverIds = ["driver0"];
  await h.dispatch();
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver1", "driver2"]);
});

test("unapproved, busy and wrong-vehicle drivers cannot receive Boda offers", async () => {
  const h = harness(4);
  h.docs.get("drivers/driver0").reviewStatus = "pending";
  h.docs.set("active_driver_rides/driver1", { rideId: "other" });
  h.docs.get("drivers/driver2").registration.vehicleType = "Car";
  await h.dispatch();
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver3"]);
});

test("a temporary presence failure releases the lease and allows a later retry", async () => {
  const h = harness(1);
  h.beforePresence(async () => { throw new Error("Temporary outage"); });
  await assert.rejects(h.dispatch(), /Temporary outage/);
  assert.equal(h.docs.get("rides/ride").dispatchLeaseUntil, null);
  h.beforePresence(null);
  h.advance(10001);
  assert.equal(await h.dispatch(), "offered");
});

test("one malformed wallet cannot block the rest of the nearby fleet", async () => {
  const h = harness(2);
  h.docs.set("driver_wallets/driver0", { balance: "bad-data" });
  await h.dispatch();
  assert.deepEqual(h.docs.get("rides/ride").offeredDriverIds, ["driver1"]);
});

test("an unanswered driver gets one retry after cooldown, not an endless notification loop", async () => {
  const h = harness(1);
  await h.dispatch();
  h.advance(30001);
  assert.equal(await h.dispatch(), "requested");
  assert.equal(h.sent.length, 1);
  h.advance(30001);
  assert.equal(await h.dispatch(), "offered");
  assert.equal(h.sent.length, 2);
  h.advance(60001);
  assert.equal(await h.dispatch(), "requested");
  assert.equal(h.sent.length, 2);
});

test("a driver becoming busy during verification is skipped at publication", async () => {
  const h = harness(1);
  const getAll = h.db.getAll;
  h.db.getAll = async (...refs) => {
    const snapshots = await getAll(...refs);
    h.docs.set("active_driver_rides/driver0", { rideId: "another-ride" });
    return snapshots;
  };
  assert.equal(await h.dispatch(), "requested");
  assert.equal(h.sent.length, 0);
});


test("completed ride presence is released during the very next dispatch", async () => {
  const h = harness();
  h.presence.driver0.activeRideId = "previous";
  h.docs.set("rides/previous", { driverId: "driver0", status: "completed" });
  h.docs.set("active_driver_rides/driver0", { rideId: "previous" });
  assert.equal(await h.dispatch(), "offered");
  assert.equal(h.presence.driver0.activeRideId, undefined);
  assert.equal(h.docs.has("active_driver_rides/driver0"), false);
  assert.equal(h.sent.length, 1);
});

test("cancelled ride presence without a lock is recovered without going offline", async () => {
  const h = harness();
  h.presence.driver0.activeRideId = "previous";
  h.docs.set("rides/previous", { driverId: "driver0", status: "cancelled" });
  assert.equal(await h.dispatch(), "offered");
  assert.equal(h.presence.driver0.isOnline, true);
});

test("active or unverified ride pointers remain busy", async () => {
  for (const previous of [null, { driverId: "driver0", status: "in_progress" },
    { driverId: "another", status: "completed" }]) {
    const h = harness();
    h.presence.driver0.activeRideId = "previous";
    if (previous) h.docs.set("rides/previous", previous);
    assert.equal(await h.dispatch(), "requested");
    assert.equal(h.presence.driver0.activeRideId, "previous");
    assert.equal(h.sent.length, 0);
  }
});

test("a newer driver lock is never released by old trip reconciliation", async () => {
  const h = harness();
  h.presence.driver0.activeRideId = "previous";
  h.docs.set("rides/previous", { driverId: "driver0", status: "completed" });
  h.docs.set("active_driver_rides/driver0", { rideId: "new-trip" });
  assert.equal(await h.dispatch(), "requested");
  assert.equal(h.docs.get("active_driver_rides/driver0").rideId, "new-trip");
  assert.equal(h.presence.driver0.activeRideId, "previous");
});
