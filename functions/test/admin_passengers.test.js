"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
function harness() {
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  class Timestamp { constructor(ms) { this.ms = ms; } toMillis() { return this.ms; } }
  let reads = 0, cursor = null, limit = 0;
  const documents = ["a", "b", "c"].map((id) => ({ id, data: () => ({ name: `Passenger ${id}`, phoneNumber: `+211${id}`, createdAt: new Timestamp(1000) }) }));
  const query = { orderBy: () => query, startAfter: (id) => { cursor = id; return query; }, limit: (n) => { limit = n; return query; }, get: async () => {
    reads++; return { docs: documents.filter((doc) => !cursor || doc.id > cursor).slice(0, limit) };
  }, doc: (id) => ({ id }) };
  const context = { exports: {}, HttpsError, Timestamp, REGION: "test", logger: { error() {} },
    onCall: (_, fn) => fn,
    require: () => ({ FieldPath: { documentId: () => "__name__" } }),
    db: { collection: () => query, getAll: async (...refs) => refs.map(() => ({ exists: false })) },
  };
  const source = fs.readFileSync(require.resolve("../admin_ops_functions"), "utf8");
  vm.runInNewContext(source.slice(source.indexOf("function requireAdmin"), source.indexOf("function ridePayload")) +
    source.slice(source.indexOf("exports.adminListPassengers")), context);
  return { handler: context.exports.adminListPassengers, reads: () => reads };
}
test("passenger lists require an administrator before reading private profiles", async () => {
  const h = harness();
  await assert.rejects(h.handler({ data: {} }), { code: "unauthenticated" });
  await assert.rejects(h.handler({ auth: { uid: "passenger", token: {} }, data: {} }), { code: "permission-denied" });
  assert.equal(h.reads(), 0);
});
test("passenger pagination does not omit accounts without creation timestamps or repeat previous pages", async () => {
  const h = harness(); const auth = { uid: "admin", token: { admin: true } };
  const first = await h.handler({ auth, data: { limit: 2 } });
  assert.equal(first.passengers.length, 2); assert.equal(first.nextCursor, "b");
  const next = await h.handler({ auth, data: { limit: 2, cursor: first.nextCursor } });
  assert.equal(next.passengers[0].passengerId, "c"); assert.equal(next.nextCursor, null);
});
test("invalid passenger cursors fail without loading profile data", async () => {
  const h = harness(); const auth = { uid: "admin", token: { admin: true } };
  await assert.rejects(h.handler({ auth, data: { cursor: "users/another" } }), { code: "invalid-argument" });
  assert.equal(h.reads(), 0);
});
