"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

function harness() {
  const records = new Map();
  const sent = [];
  const ref = (path) => ({ path,
    get: async () => ({ get: (key) => records.get(path)?.[key] }),
    create: async (value) => {
      if (records.has(path)) throw Object.assign(new Error("exists"), { code: 6 });
      records.set(path, value);
    },
    update: async (value) => records.set(path, { ...records.get(path), ...value }),
  });
  const db = { collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    runTransaction: async (work) => work({ get: (r) => r.get(),
      set: (r, value) => records.set(r.path, value), delete: (r) => records.delete(r.path) }),
  };
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const exports = {};
  const requireMock = (name) => {
    if (name === "firebase-admin/firestore") return { getFirestore: () => db, FieldValue: { serverTimestamp: () => "now" } };
    if (name === "firebase-admin/messaging") return { getMessaging: () => ({ send: async (msg) => sent.push(msg) }) };
    if (name === "firebase-functions/v2/https") return { HttpsError, onCall: (_, fn) => fn };
    if (name === "firebase-functions/v2/firestore") return { onDocumentCreated: (_, fn) => fn, onDocumentUpdated: (_, fn) => fn };
    if (name === "firebase-functions") return { logger: { warn: () => {} } };
    if (name === "./notification_logic") return require("../notification_logic");
    return require(name);
  };
  vm.runInNewContext(fs.readFileSync(require.resolve("../app_notification_functions"), "utf8"), { exports, require: requireMock });
  return { exports, records, sent };
}

test("passenger token registration rejects unsigned users and invalid tokens", async () => {
  const h = harness();
  await assert.rejects(h.exports.registerPassengerPushToken({ data: {} }), { code: "unauthenticated" });
  await assert.rejects(h.exports.registerPassengerPushToken({ auth: { uid: "p1" }, data: { token: "short" } }), { code: "invalid-argument" });
  assert.equal(h.records.size, 0);
});

test("switching accounts transfers the same installation token away from the old passenger", async () => {
  const h = harness();
  const data = { token: "installation-token-that-is-long-enough" };
  await h.exports.registerPassengerPushToken({ auth: { uid: "p1" }, data });
  await h.exports.registerPassengerPushToken({ auth: { uid: "p2" }, data });
  assert.equal(h.records.has("passenger_push_tokens/p1"), false);
  assert.equal(h.records.get("passenger_push_tokens/p2").token, data.token);
});

test("duplicate ride events deliver once and fare updates deliver no extra alert", async () => {
  const h = harness();
  h.records.set("passenger_push_tokens/p1", { token: "passenger-token-that-is-long-enough" });
  const event = { params: { rideId: "r1" }, data: {
    before: { data: () => ({ status: "offered" }) },
    after: { data: () => ({ status: "accepted", passengerId: "p1" }) },
  } };
  await h.exports.notifyPassengerRideUpdate(event);
  await h.exports.notifyPassengerRideUpdate(event);
  assert.equal(h.sent.length, 1);
  event.data.before.data = () => ({ status: "accepted" });
  await h.exports.notifyPassengerRideUpdate(event);
  assert.equal(h.sent.length, 1);
});

test("fresh news alerts but historical unread inbox migration does not", async () => {
  const h = harness();
  h.records.set("driver_push_tokens/d1", { token: "driver-token-that-is-long-enough" });
  const event = { params: { uid: "d1", notificationId: "n1" }, data: {
    data: () => ({ type: "news", title: "News", message: "Details", createdAt: { toMillis: () => Date.now() - 86400000 } }),
  } };
  await h.exports.notifyDriverInbox(event);
  assert.equal(h.sent.length, 0);
  event.data.data = () => ({ type: "discount", title: "Discount", message: "Details", createdAt: { toMillis: () => Date.now() } });
  await h.exports.notifyDriverInbox(event);
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].android.notification.channelId, "alpha_updates_v1");
});
