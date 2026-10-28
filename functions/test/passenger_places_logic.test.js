"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createPassengerPlaces } = require("../passenger_places_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const search = { auth: { uid: "p1" }, data: { query: "Juba", latitude: 4.85, longitude: 31.57, sessionToken: "abcdefghijklmnop123456" } };
const details = { auth: search.auth, data: { placeId: "ChIJtestplace", sessionToken: search.data.sessionToken } };
const secret = "server-only-test-key";
function harness() {
  const records = new Map([["account_roles/p1", { role: "passenger" }]]);
  const calls = [];
  const logs = [];
  let time = 1000, response;
  const snapshot = ref => ({ exists: records.has(ref.path), data: () => records.get(ref.path) });
  const db = { collection: name => ({ doc: uid => ({ path: `${name}/${uid}` }) }),
    runTransaction: async fn => fn({ getAll: async (...refs) => refs.map(snapshot), set: (ref, data) => records.set(ref.path, data) }) };
  const fetchImpl = async (url, options) => {
    calls.push({ url, options });
    if (response instanceof Error) throw response;
    return response || { ok: true, json: async () => url.includes(":autocomplete") ? {
      suggestions: [{ placePrediction: { placeId: "ChIJtestplace", text: { text: "Juba Market, South Sudan" },
        structuredFormat: { mainText: { text: "Juba Market" }, secondaryText: { text: "South Sudan" } } } }],
    } : { id: "ChIJtestplace", formattedAddress: "Juba, South Sudan", location: { latitude: 4.85, longitude: 31.57 } } };
  };
  return { records, calls, logs, api: createPassengerPlaces({ db, HttpsError, apiKey: () => secret, fetchImpl, clock: () => time, logger: { warn: (...args) => logs.push(args) } }),
    advance: value => { time += value; }, respond: value => { response = value; } };
}

test("search and details keep the key on the server and preserve location and billing session", async () => {
  const h = harness();
  const result = await h.api.search(search);
  const place = await h.api.details(details);
  assert.equal(result.results[0].primaryText, "Juba Market");
  assert.equal(place.address, "Juba, South Sudan");
  assert.equal(h.calls[0].options.headers["X-Goog-Api-Key"], secret);
  const body = JSON.parse(h.calls[0].options.body);
  assert.deepEqual(body.locationBias.circle.center, { latitude: 4.85, longitude: 31.57 });
  assert.equal(body.locationBias.circle.radius, 50000);
  assert.equal(new URL(h.calls[1].url).searchParams.get("sessionToken"), body.sessionToken);
  assert.notEqual(body.sessionToken, search.data.sessionToken);
  assert.equal(JSON.stringify({ result, place }).includes(secret), false);
});

test("only active registered passengers can use the server, even on cached results", async () => {
  const h = harness();
  await assert.rejects(h.api.search({ ...search, auth: null }), { code: "unauthenticated" });
  for (const account of [null, { role: "driver" }, { role: "passenger", deletionPending: true }]) {
    h.records.set("account_roles/p1", account);
    await assert.rejects(h.api.search(search), { code: "permission-denied" });
    await assert.rejects(h.api.details(details), { code: "permission-denied" });
  }
  assert.equal(h.calls.length, 0);
  h.records.set("account_roles/p1", { role: "passenger" }); await h.api.search(search);
  h.records.set("account_roles/p1", { role: "passenger", deletionPending: true });
  await assert.rejects(h.api.search(search), { code: "permission-denied" });
  assert.equal(h.calls.length, 1);
});

test("invalid inputs cannot call Google or supply their own upstream URLs", async () => {
  const h = harness();
  for (const change of [{ query: "a" }, { query: "x".repeat(181) }, { latitude: 91 }, { longitude: Infinity },
    { latitude: "4.85" }, { sessionToken: "too-short" }]) {
    await assert.rejects(h.api.search({ ...search, data: { ...search.data, ...change } }), { code: "invalid-argument" });
  }
  await assert.rejects(h.api.details({ ...details, data: { ...details.data, placeId: "https://attacker.invalid/key" } }), { code: "invalid-argument" });
  assert.equal(h.calls.length, 0);
});

test("cached queries avoid duplicate Google calls while distinct map biases stay independent", async () => {
  const h = harness(); await h.api.search(search); await h.api.search(search);
  assert.equal(h.calls.length, 1);
  await h.api.search({ ...search, data: { ...search.data, latitude: 9 } });
  assert.equal(h.calls.length, 2);
});

test("sessions are isolated between passengers", async () => {
  const h = harness(); h.records.set("account_roles/p2", { role: "passenger" });
  await h.api.search(search);
  await h.api.search({ ...search, auth: { uid: "p2" } });
  assert.notEqual(JSON.parse(h.calls[0].options.body).sessionToken, JSON.parse(h.calls[1].options.body).sessionToken);
});

test("rate limits apply before cached responses and reset in the next minute", async () => {
  const h = harness();
  for (let i = 0; i < 100; i++) await h.api.search(search);
  await assert.rejects(h.api.search(search), { code: "resource-exhausted" });
  assert.equal(h.calls.length, 1);
  h.advance(60000); await h.api.search(search);
  assert.equal(h.records.get("passenger_places_limits/p1").count, 1);
});

test("upstream failures never leak Google error bodies or the secret", async () => {
  for (const failure of [{ ok: false, status: 403, text: async () => secret },
    { ok: false, status: 429, text: async () => secret }, new Error(`request failed ${secret}`)]) {
    const h = harness(); h.respond(failure);
    await assert.rejects(h.api.search(search), error => {
      assert.equal(error.message.includes(secret), false);
      assert.ok(["failed-precondition", "unavailable", "resource-exhausted"].includes(error.code)); return true;
    });
  }
});

test("unusable place coordinates do not become a destination", async () => {
  const h = harness(); h.respond({ ok: true, json: async () => ({ formattedAddress: "broken", location: { latitude: 999, longitude: 0 } }) });
  await assert.rejects(h.api.details(details), { code: "invalid-argument" });
});


test("provider configuration errors expose a safe code and allowlisted diagnostics only", async () => {
  const h = harness();
  h.respond({ ok: false, status: 403, json: async () => ({ error: {
    status: "PERMISSION_DENIED", message: `secret ${secret}`, details: [{ reason: "API_KEY_SERVICE_BLOCKED", metadata: { key: secret } }],
  } }) });
  await assert.rejects(h.api.search(search), { code: "failed-precondition" });
  assert.deepEqual(h.logs, [["passenger_places_provider_failure", {
    operation: "autocomplete", httpStatus: 403, providerStatus: "PERMISSION_DENIED", reason: "API_KEY_SERVICE_BLOCKED",
  }]]);
  assert.equal(JSON.stringify(h.logs).includes(secret), false);
});

test("untrusted provider status and reason cannot enter diagnostics", async () => {
  const h = harness();
  h.respond({ ok: false, status: 503, json: async () => ({ error: { status: secret, details: [{ reason: secret }] } }) });
  await assert.rejects(h.api.search(search), { code: "unavailable" });
  assert.equal(JSON.stringify(h.logs).includes(secret), false);
});
