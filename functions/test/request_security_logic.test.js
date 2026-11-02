"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createRequestSecurity } = require("../request_security_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function harness({ user = {}, role = {}, missing = false } = {}) {
  const records = new Map(); let now = 100000;
  const snapshot = data => ({ data: () => data, get: key => data?.[key] });
  const db = { collection: collection => ({ doc: id => ({ path: `${collection}/${id}`, get: async () => snapshot(role) }) }),
    runTransaction: async work => work({ get: async ref => snapshot(records.get(ref.path)), set: (ref, data) => records.set(ref.path, data) }) };
  const security = createRequestSecurity({ db, HttpsError, clock: () => now,
    auth: { getUser: async () => { if (missing) throw { code: "auth/user-not-found" }; return { phoneNumber: "+211922222222", ...user }; } } });
  return { ...security, records, advance: ms => { now += ms; } };
}
const request = { auth: { uid: "person", token: { auth_time: 100, phone_number: "+211922222222" } } };
test("disabled, removed, revoked and deletion-fenced accounts cannot call the backend", async () => {
  for (const options of [{ user: { disabled: true } }, { missing: true }, { user: { tokensValidAfterTime: new Date(101000).toISOString() } }, { role: { deletionPending: true } }, { role: { deleted: true } }]) {
    await assert.rejects(harness(options).guard(request), e => ["unauthenticated", "permission-denied"].includes(e.code));
  }
});
test("valid sessions use second precision when checking revocation", async () => {
  await harness({ user: { tokensValidAfterTime: new Date(100900).toISOString() } }).guard(request);
});
test("request budgets are shared persistently, reset after the window and never store raw identity", async () => {
  const h = harness(); await h.limit("private-uid", "test", 2, 60000); await h.limit("private-uid", "test", 2, 60000);
  await assert.rejects(h.limit("private-uid", "test", 2, 60000), e => e.code === "resource-exhausted");
  assert.ok(!JSON.stringify([...h.records]).includes("private-uid"));
  h.advance(60001); await h.limit("private-uid", "test", 2, 60000);
});
test("anonymous preflight is bounded by hashed network identity", async () => {
  const h = harness();
  for (let i = 0; i < 120; i++) await h.guard({ rawRequest: { ip: "192.0.2.1" } });
  await assert.rejects(h.guard({ rawRequest: { ip: "192.0.2.1" } }), e => e.code === "resource-exhausted");
  assert.ok(!JSON.stringify([...h.records]).includes("192.0.2.1"));
});
test("oversized callable bodies are rejected before authentication or database work", async () => {
  await assert.rejects(harness().guard({ ...request, data: { value: "x".repeat(33000) } }), e => e.code === "invalid-argument");
});

test("anonymous or other unverified Firebase accounts cannot spend server API budget", async () => {
  await assert.rejects(harness().guard({ auth: { uid: "person", token: { auth_time: 100 } } }), e => e.code === "permission-denied");
  await assert.rejects(harness({ user: { phoneNumber: "+211933333333" } }).guard(request), e => e.code === "permission-denied");
  await harness().guard({ auth: { uid: "staff", token: { auth_time: 100, admin: true } } });
});
