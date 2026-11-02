"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createPassengerLocations } = require("../passenger_locations_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function harness(options = {}) {
  const now = 100000;
  const point = { driverId: "driver", latitude: 4.851734, longitude: 31.582541, heading: 37, updatedAt: now, isOnline: true, presenceId: "private-session", ...options.point };
  const profiles = { "account_roles/passenger": { role: "passenger", ...options.role },
    "active_passenger_rides/passenger": { rideId: "ride" },
    "rides/ride": { passengerId: "passenger", driverId: "driver", status: "accepted", ...options.ride },
    "drivers/driver": { reviewStatus: "approved", registration: { vehicleType: "Boda" }, ...options.profile },
    "driver_wallets/driver": { balance: 10000 },
    ...(options.lock ? { "active_driver_rides/driver": { rideId: "private-other-ride" } } : {}) };
  const snapshot = path => ({ exists: Boolean(profiles[path]), data: () => profiles[path], get: key => profiles[path]?.[key] });
  const refs = []; const reads = [];
  const query = { orderByChild() { return this; }, startAt() { return this; }, endAt() { return this; }, limitToFirst(n) { assert.equal(n, 200); return this; }, get: async () => ({ val: () => ({ driver: point }) }) };
  const api = createPassengerLocations({ HttpsError, clock: () => now,
    limit: async () => {}, db: { collection: name => ({ doc: id => ({ path: `${name}/${id}`, get: async () => snapshot(`${name}/${id}`) }) }), getAll: async (...values) => { refs.push(...values); return values.map(ref => snapshot(ref.path)); } },
    realtimeDb: { ref: path => { reads.push(path); return path === "driver_locations" ? query : { get: async () => ({ val: () => point }) }; } } });
  const request = (data = {}, auth = { uid: "passenger" }) => ({ auth, data });
  return { reads, nearby: (data = { latitude: point.latitude, longitude: point.longitude }, auth) => api.nearby(request(data, auth)),
    assigned: (driverId = "driver", auth) => api.assigned(request({ driverId }, auth)) };
}
test("nearby previews expose coarse anonymous markers without private driver/session/ride data", async () => {
  const result = await harness().nearby(); assert.equal(result.drivers.length, 1);
  const driver = result.drivers[0]; assert.match(driver.driverId, /^nearby_/);
  assert.equal(driver.latitude, 4.852); assert.equal(driver.longitude, 31.583); assert.equal(driver.heading, 30);
  assert.equal(driver.presenceId, undefined); assert.equal(driver.activeRideId, undefined);
});
test("unsigned, wrong-role and deleted users cannot read the fleet", async () => {
  const h = harness(); await assert.rejects(h.nearby(undefined, null), e => e.code === "unauthenticated"); assert.equal(h.reads.length, 0);
  for (const role of [{ role: "driver" }, { deletionPending: true }]) await assert.rejects(harness({ role }).nearby(), e => e.code === "permission-denied");
});
test("invalid map centers are rejected before database location reads", async () => {
  for (const latitude of [NaN, Infinity, 91, "4.8"]) {
    const h = harness(); await assert.rejects(h.nearby({ latitude, longitude: 31 }), e => e.code === "invalid-argument"); assert.equal(h.reads.length, 0);
  }
});
test("busy, unapproved, stale, future-dated and distant vehicles are excluded", async () => {
  for (const options of [{ lock: true }, { profile: { reviewStatus: "pending" } }, { point: { activeRideId: "other" } }, { point: { updatedAt: 0 } }, { point: { updatedAt: 999999 } }]) assert.equal((await harness(options).nearby()).drivers.length, 0);
  assert.equal((await harness().nearby({ latitude: 0, longitude: 0 })).drivers.length, 0);
});
test("exact tracking requires the active passenger assignment and rejects other driver IDs", async () => {
  const h = harness(); await assert.rejects(h.assigned("other"), e => e.code === "permission-denied"); assert.equal(h.reads.length, 0);
  const result = await h.assigned(); assert.equal(result.drivers[0].latitude, 4.851734); assert.equal(result.drivers[0].driverId, "driver");
  for (const ride of [{ passengerId: "someone-else" }, { status: "completed" }, { status: "cancelled" }]) assert.equal((await harness({ ride }).assigned()).drivers.length, 0);
});
