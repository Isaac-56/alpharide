"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createAdminAccountDeleter } = require("../admin_account_logic");
const { hashPhoneNumber } = require("../account_role_logic");
const phone = "+211912345678", uid = "u1", hash = hashPhoneNumber(phone);
const request = { auth: { uid: "admin1", token: { admin: true } }, data: { uid, role: "passenger", confirmPhone: phone } };
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function harness(extra = {}) {
  const records = new Map(Object.entries({ "users/u1": { uid, phoneNumber: phone },
    "account_roles/u1": { role: "passenger", phoneHash: hash },
    [`identity_registry/${hash}`]: { uid, role: "passenger" },
    [`users/${phone}`]: { phoneNumber: phone }, ...extra }));
  const effects = [];
  let user = { uid, phoneNumber: phone };
  let failCleanup = false;
  const snap = (ref) => ({ exists: records.has(ref.path), data: () => records.get(ref.path), ref });
  const ref = (path) => ({ path, get: async () => snap(ref(path)), delete: async () => records.delete(path), listCollections: async () => {
    const children = new Set([...records.keys()].filter(key => key.startsWith(`${path}/`)).map(key => key.split("/")[2]));
    return [...children].map(child => ref(`${path}/${child}`));
  } });
  const db = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`), where: (field, _, value) => ({ get: async () => ({
      docs: [...records].filter(([path, data]) => path.startsWith(`${name}/`) && data[field] === value).map(([path]) => snap(ref(path))),
    }) }) }),
    runTransaction: async (fn) => {
      const writes = [];
      const result = await fn({ get: async (r) => snap(r), getAll: async (...refs) => refs.map(snap),
        set: (r, data, options) => writes.push(() => records.set(r.path, options?.merge ? { ...records.get(r.path), ...data } : data)),
        delete: (r) => writes.push(() => records.delete(r.path)) });
      writes.forEach(fn => fn()); return result;
    },
    recursiveDelete: async (r) => {
      if (failCleanup) throw new Error("temporary storage/database outage");
      effects.push(`delete:${r.path}`);
      for (const path of records.keys()) if (path === r.path || path.startsWith(`${r.path}/`)) records.delete(path);
    },
  };
  const missing = () => Object.assign(new Error("missing"), { code: "auth/user-not-found" });
  const auth = { getUser: async () => { if (!user) throw missing(); return user; },
    updateUser: async () => { if (!user) throw missing(); effects.push("auth:disable"); },
    revokeRefreshTokens: async () => { if (!user) throw missing(); effects.push("auth:revoke"); },
    deleteUser: async () => { if (!user) throw missing(); user = null; effects.push("auth:delete"); } };
  const storage = { bucket: () => ({ deleteFiles: async ({ prefix }) => effects.push(`storage:${prefix}`),
    file: (path) => ({ delete: async () => effects.push(`storage:${path}`) }) }) };
  const realtimeDb = { ref: (path) => ({ set: async () => effects.push(`rtdb:block:${path}`), remove: async () => effects.push(`rtdb:delete:${path}`) }) };
  return { records, effects, setUser: value => { user = value; }, fail: value => { failCleanup = value; },
    remove: createAdminAccountDeleter({ db, auth, storage, realtimeDb, HttpsError, now: () => new Date(0) }) };
}

test("admin deletion clears login, documents, private subcollections and phone binding, preserving business history", async () => {
  const h = harness({ "users/u1/notifications/n1": {}, "rides/r1": { passengerId: uid, status: "completed" },
    "ride_receipts/r1": { passengerId: uid }, "passenger_push_token_owners/t1": { uid },
    "passenger_push_token_owners/t2": { uid: "someone_else" } });
  assert.equal((await h.remove(request)).deleted, true);
  for (const path of ["users/u1", "users/u1/notifications/n1", `users/${phone}`, `identity_registry/${hash}`, "passenger_push_token_owners/t1"]) assert.equal(h.records.has(path), false, path);
  assert.equal(h.records.has("rides/r1"), true);
  assert.equal(h.records.has("ride_receipts/r1"), true);
  assert.equal(h.records.has("passenger_push_token_owners/t2"), true);
  assert.deepEqual(h.records.get("account_roles/u1"), { deletionPending: true, deleted: true, deletedAt: new Date(0) });
  assert.ok(h.effects.includes("auth:disable") && h.effects.includes("auth:revoke") && h.effects.includes("auth:delete"));
  assert.ok(h.effects.includes(`storage:user_photos/${phone}.jpg`));
  assert.ok(h.effects.includes("storage:users/u1/"));
  assert.equal(h.records.get("account_deletions/u1").state, "completed");
});

test("no unprivileged account, staff account, self deletion or mismatched phone can trigger cleanup", async () => {
  for (const changed of [ { auth: null }, { auth: { uid: "x", token: {} } },
    { auth: { uid, token: { admin: true } } }, { data: { ...request.data, confirmPhone: "+211923456789" } } ]) {
    const h = harness(); await assert.rejects(h.remove({ ...request, ...changed })); assert.deepEqual(h.effects, []);
  }
  const h = harness(); h.setUser({ uid, phoneNumber: phone, customClaims: { admin: true } });
  await assert.rejects(h.remove(request), { code: "failed-precondition" }); assert.deepEqual(h.effects, []);
});

test("active driver and passenger locks block deletion, even when the other profile type is selected", async () => {
  for (const lock of ["active_driver_rides", "active_passenger_rides"]) {
    const h = harness({ [`${lock}/u1`]: { rideId: "r1" }, "rides/r1": { status: "in_progress" } });
    await assert.rejects(h.remove(request), { code: "failed-precondition" });
    assert.deepEqual(h.effects, []); assert.equal(h.records.has("account_deletions/u1"), false);
  }
});

test("completed ride pointers allow cleanup but unsettled balances do not", async () => {
  const h = harness({ "active_passenger_rides/u1": { rideId: "r1" }, "rides/r1": { status: "completed" } });
  await h.remove(request);
  for (const balance of [100, -10, "not-a-balance"]) {
    const unsettled = harness({ "driver_wallets/u1": { balance } });
    await assert.rejects(unsettled.remove(request), { code: "failed-precondition" }); assert.deepEqual(unsettled.effects, []);
  }
});

test("partial cleanup is fenced and can resume after an outage", async () => {
  const h = harness(); h.fail(true);
  await assert.rejects(h.remove(request), /temporary/);
  assert.equal(h.records.get("account_roles/u1").deletionPending, true);
  assert.equal(h.records.get("account_deletions/u1").state, "deleting");
  assert.equal(h.effects.includes("auth:delete"), false);
  h.fail(false); await h.remove(request);
  assert.equal(h.records.get("account_deletions/u1").state, "completed");
});

test("completed retries cannot delete a newly registered account or its legacy photo", async () => {
  const h = harness(); await h.remove(request);
  h.records.set(`identity_registry/${hash}`, { uid: "new_uid", role: "driver" });
  h.records.set(`users/${phone}`, { uid: "new_uid" });
  const before = h.effects.length;
  await h.remove(request);
  assert.equal(h.effects.length, before);
  assert.equal(h.records.get(`identity_registry/${hash}`).uid, "new_uid");
  assert.equal(h.records.get(`users/${phone}`).uid, "new_uid");
});

test("foreign registration indexes and photos are never deleted using an editable orphan profile phone", async () => {
  const h = harness({ [`identity_registry/${hash}`]: { uid: "other_uid", role: "passenger" } });
  await assert.rejects(h.remove(request), { code: "failed-precondition" }); assert.deepEqual(h.effects, []);
  const orphan = harness(); orphan.setUser(null); await orphan.remove(request);
  assert.equal(orphan.effects.includes(`storage:user_photos/${phone}.jpg`), false);
  assert.equal(orphan.records.has(`users/${phone}`), true);
});

test("driver deletion removes selfie and licence directories and preserves settled wallet history", async () => {
  const h = harness({ "drivers/u1": { phoneNumber: phone }, "account_roles/u1": { role: "driver", phoneHash: hash },
    [`identity_registry/${hash}`]: { uid, role: "driver" }, "driver_wallets/u1": { balance: 0 },
    "driver_wallets/u1/transactions/t1": { amount: 10 }, "driver_photo_checks/u1": { storagePath: "drivers/u1/documents/photo_checks/face.jpg" } });
  await h.remove({ ...request, data: { ...request.data, role: "driver" } });
  assert.equal(h.records.has("drivers/u1"), false); assert.equal(h.records.has("driver_photo_checks/u1"), false);
  assert.equal(h.records.has("driver_wallets/u1/transactions/t1"), true);
  assert.ok(h.effects.includes("storage:drivers/u1/"));
});
