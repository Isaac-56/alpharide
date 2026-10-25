"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const logic = require("../account_role_logic");

function harness(records = {}, lookup = async () => ({ uid: "u1" })) {
  const reads = [], writes = [], batches = [];
  const snapshot = (ref) => ({ ref, exists: records[ref.path] != null,
    data: () => records[ref.path] });
  const db = {
    collection: (name) => ({
      doc: (id) => {
        const ref = { path: `${name}/${id}` };
        ref.get = async () => { reads.push(ref.path); return snapshot(ref); };
        return ref;
      },
      where: () => ({ limit: () => ({ get: async () => {
        reads.push(`${name}/query`); return { docs: [], empty: true };
      } }) }),
    }),
    getAll: async (...refs) => { reads.push(...refs.map(r => r.path)); return refs.map(snapshot); },
    runTransaction: async (callback) => callback({
      getAll: async (...refs) => { batches.push(refs.map(r => r.path)); return refs.map(snapshot); },
      set: (ref, data) => writes.push({ path: ref.path, data }),
    }),
  };
  class HttpsError extends Error {
    constructor(code, message, details) { super(message); this.code = code; this.details = details; }
  }
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(require.resolve("../role_functions"), "utf8"), {
    module, exports: module.exports,
    require: (name) => {
      if (name === "firebase-admin/auth") return { getAuth: () => ({ getUserByPhoneNumber: lookup }) };
      if (name === "firebase-admin/firestore") return { getFirestore: () => db, FieldValue: { serverTimestamp: () => "now" } };
      if (name === "firebase-functions") return { logger: { error() {} } };
      if (name === "firebase-functions/v2/https") return { HttpsError, onCall: (_, handler) => handler };
      if (name === "./account_role_logic") return logic;
      throw Error(`Unexpected dependency ${name}`);
    },
  });
  return { api: module.exports, reads, writes, batches };
}
const phone = "+211912345678";
const hash = logic.hashPhoneNumber(phone);
const request = { auth: { uid: "u1", token: { phone_number: phone } }, data: { role: "passenger", phoneNumber: phone } };

test("existing login validates every record in one batch without rewriting its role", async () => {
  const h = harness({ "account_roles/u1": { role: "passenger", phoneHash: hash },
    [`identity_registry/${hash}`]: { role: "passenger", uid: "u1" }, "users/u1": {} });
  const result = await h.api.claimAccountRole(request);
  assert.equal(result.claimed, true);
  assert.equal(h.batches.length, 1);
  assert.equal(h.batches[0].length, 5);
  assert.equal(h.writes.length, 0);
});

test("new registration still atomically creates both role records", async () => {
  const h = harness();
  const result = await h.api.claimAccountRole(request);
  assert.equal(result.role, "passenger");
  assert.equal(h.writes.length, 2);
});

test("legacy account migration repairs the missing identity registry", async () => {
  const h = harness({ "account_roles/u1": { role: "passenger", phoneHash: hash }, "users/u1": {} });
  const result = await h.api.checkAccountRole(request);
  assert.equal(result.migrated, true);
  assert.deepEqual(h.writes.map(w => w.path), [`identity_registry/${hash}`]);
});

test("conflicting driver profile still blocks passenger login without writes", async () => {
  const h = harness({ "drivers/u1": {} });
  await assert.rejects(h.api.claimAccountRole(request), e => e.code === "failed-precondition");
  assert.equal(h.writes.length, 0);
});

test("preflight overlaps independent Firestore reads with Auth lookup", async () => {
  let finishLookup;
  const lookup = new Promise(resolve => { finishLookup = resolve; });
  const h = harness({}, () => lookup);
  const pending = h.api.preflightAccountRole(request);
  assert.ok(h.reads.includes(`identity_registry/${hash}`));
  assert.ok(h.reads.includes("drivers/query"));
  finishLookup({ uid: "u1" });
  assert.equal((await pending).eligible, true);
  assert.ok(h.reads.includes("drivers/u1"));
});

test("preflight still rejects an existing driver found by UID", async () => {
  const h = harness({ "drivers/u1": {} });
  await assert.rejects(h.api.preflightAccountRole(request), e => e.code === "failed-precondition");
});


test("a deleted UID cannot reclaim the phone through an unexpired old ID token", async () => {
  const h = harness({ "account_roles/u1": { deletionPending: true, deleted: true } });
  await assert.rejects(h.api.claimAccountRole(request), { code: "failed-precondition" });
  assert.equal(h.writes.length, 0);
});

test("a fresh Auth UID can register the released phone while the deleted UID stays blocked", async () => {
  const h = harness({ "account_roles/u1": { deletionPending: true, deleted: true } });
  const result = await h.api.claimAccountRole({ ...request, auth: { uid: "new_uid", token: { phone_number: phone } } });
  assert.equal(result.claimed, true);
  assert.deepEqual(h.writes.map(write => write.path), ["account_roles/new_uid", `identity_registry/${hash}`]);
});
