"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

async function recover({ status = "in_progress", newerLock = false, completeBeforeTransaction = false } = {}) {
  let lock = { driverId: "driver", rideId: "old" };
  const ride = { driverId: "driver", status };
  let presence = { isOnline: true, activeRideId: "old", latitude: 4.85, longitude: 31.6 };
  let busyWrites = 0;
  const snapshot = (value) => ({ exists: Boolean(value), get: (key) => value?.[key] });
  const activeRef = { kind: "lock", get: async () => snapshot(lock) };
  const rideRef = { kind: "ride", get: async () => snapshot(ride) };
  const newRide = { driverId: "driver", status: "in_progress" };
  const newRideRef = { kind: "newRide" };
  const ctx = { exports: {}, Timestamp: { now: () => 1 }, FieldValue: { serverTimestamp: () => 1 },
    driverRideLock: async (_, id) => ({ rideRef: id === "new" ? newRideRef : rideRef, value: "active" }),
    closeStaleActiveRide: async () => {},
    db: { collection: () => ({ doc: () => activeRef }), runTransaction: async (work) => {
      if (newerLock) { lock = { driverId: "driver", rideId: "new" }; presence.activeRideId = "new"; newerLock = false; }
      if (completeBeforeTransaction) { ride.status = "completed"; lock = null; completeBeforeTransaction = false; }
      const writes = [];
      const result = await work({ get: async (ref) => snapshot(ref.kind === "ride" ? ride : ref.kind === "newRide" ? newRide : lock),
        set: (_, data) => writes.push(() => { lock = data; }), delete: () => writes.push(() => { lock = null; }) });
      writes.forEach((fn) => fn()); return result;
    } },
    realtimeDb: { ref: () => ({ get: async () => ({ exists: () => true, val: () => presence }),
      update: async (data) => { busyWrites++; presence = { ...presence, ...data }; },
      transaction: async (fn) => { const next = fn(presence); if (next !== undefined) presence = next; },
    }) },
  };
  const source = fs.readFileSync(require.resolve("../lifecycle_functions"), "utf8");
  vm.runInNewContext(source.slice(source.indexOf("async function syncDriverPresenceRide"), source.indexOf("function rideActivityAt")) +
    source.slice(source.indexOf("async function deleteMatchingActiveDriverRide"), source.indexOf("async function driverRideLock")) +
    source.slice(source.indexOf("async function prepareDriverActiveRide"), source.indexOf("exports.prepareDriverAvailability")) +
    "\nexports.recover = prepareDriverActiveRide;", ctx);
  const result = await ctx.exports.recover("driver");
  return { result, lock, presence, busyWrites };
}
test("completion racing availability recovery cannot recreate a terminal lock", async () => {
  const h = await recover({ completeBeforeTransaction: true });
  assert.equal(h.result, null); assert.equal(h.lock, null);
  assert.equal(h.presence.activeRideId, undefined); assert.equal(h.presence.isOnline, true);
});
test("active recovery preserves its lock without writing another busy presence pointer", async () => {
  const h = await recover(); assert.equal(h.result, "old"); assert.equal(h.busyWrites, 0);
});
test("old recovery does not clear a newer ride lock or newer presence pointer", async () => {
  const h = await recover({ newerLock: true, status: "completed" });
  assert.equal(h.lock.rideId, "new"); assert.equal(h.presence.activeRideId, "new");
});
