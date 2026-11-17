"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createWhatsAppAuth } = require("../whatsapp_auth_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function fixture() {
  const rows = new Map(), calls = [], tokens = [], limits = [];
  let now = 1000000, seq = 0, user = { uid: "existing", phoneNumber: "+211922049035" };
  let registeredRole = null;
  let deleted = false, result = { success: true }, providerError = null, hold = null;
  const service = createWhatsAppAuth({
    HttpsError, clock: () => now, random: () => (++seq).toString(16).padStart(64, "0"),
    store: {
      async mutate(key, fn) { rows.set(key, fn(rows.get(key) || {})); },
      async assertRole(uid, phone, role) {
        if (registeredRole && registeredRole !== role)
          throw new HttpsError("failed-precondition", "Use a different phone number for the other app.");
      },
      async isDeleted() { return deleted; },
    },
    async limit(...args) { limits.push(args); },
    async provider(path, body) {
      calls.push({ path, body });
      if (providerError) throw providerError;
      if (path) { if (hold) await hold; return result; }
      return { id: "vrf_test", status: "pending", last_channel: "whatsapp",
        expires_at: new Date(now + 600000).toISOString() };
    },
    auth: {
      async getUserByPhoneNumber() {
        if (user) return user;
        throw Object.assign(new Error(), { code: "auth/user-not-found" });
      },
      async createUser(data) { user = { uid: "new-user", ...data }; return user; },
      async createCustomToken(uid) { tokens.push(uid); return "signed-token"; },
    },
  });
  const request = data => ({ app: { appId: "passenger-app" }, rawRequest: { ip: "test-ip" }, data });
  const start = (phoneNumber = "+211922049035") => service.start(request({ phoneNumber, role: "passenger" }));
  const check = id => service.check(request({ verificationId: id, code: "123456" }));
  return { rows, calls, tokens, limits, service, request, start, check,
    setRole: role => { registeredRole = role; },
    tick: ms => { now += ms; }, setUser: v => { user = v; },
    setDeleted: () => { deleted = true; }, setResult: v => { result = v; },
    setError: v => { providerError = v; }, setHold: v => { hold = v; } };
}
test("WhatsApp only, supported +211 prefixes, and existing UID preserved", async () => {
  for (const number of ["+211922049035", "+211912049035", "+211982049035", "+211122049035", "+211822049035"]) {
    const f = fixture();
    const sent = await f.start(number);
    assert.deepEqual(f.calls[0].body.options.channels, ["whatsapp"]);
    assert.equal(f.calls[0].body.to.phone_number, number);
    assert.deepEqual(await f.check(sent.verificationId), { customToken: "signed-token" });
    assert.deepEqual(f.tokens, ["existing"]);
    await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
    assert.equal(f.tokens.length, 1);
    assert.equal(f.limits.filter(x => x[1].includes("send")).length, 3);
  }
});
test("missing App Check and foreign numbers never call Bird", async () => {
  const f = fixture();
  await assert.rejects(f.service.start({ data: {} }), { code: "unauthenticated" });
  await assert.rejects(f.start("+251922049035"), { code: "invalid-argument" });
  await assert.rejects(f.start("+211022049035"), { code: "invalid-argument" });
  assert.equal(f.calls.length, 0);
});
test("new accounts are created only after successful OTP", async () => {
  const f = fixture(); f.setUser(null);
  const sent = await f.start();
  f.setResult({ success: false, reason: "incorrect_code" });
  await assert.rejects(f.check(sent.verificationId), { code: "invalid-argument" });
  assert.deepEqual(f.tokens, []);
  f.setResult({ success: true });
  await f.check(sent.verificationId);
  assert.deepEqual(f.tokens, ["new-user"]);
});
test("resends enforce cooldown and invalidate older challenge", async () => {
  const f = fixture();
  const first = await f.start();
  await assert.rejects(f.start(), { code: "resource-exhausted" });
  f.tick(61000);
  const second = await f.start();
  await assert.rejects(f.check(first.verificationId), { code: "failed-precondition" });
  await f.check(second.verificationId);
});
test("five wrong codes exhaust the local challenge", async () => {
  const f = fixture(); const sent = await f.start();
  f.setResult({ success: false, reason: "incorrect_code" });
  for (let i = 0; i < 5; i++) await assert.rejects(f.check(sent.verificationId), { code: "invalid-argument" });
  await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
  assert.equal(f.calls.filter(x => x.path).length, 5);
});
test("expired, tampered and cross-app challenges cannot mint tokens", async () => {
  const f = fixture(); const sent = await f.start();
  await assert.rejects(f.check(sent.verificationId.slice(0, -1) + "f"), { code: "failed-precondition" });
  const req = f.request({ verificationId: sent.verificationId, code: "123456" });
  req.app.appId = "other-app";
  await assert.rejects(f.service.check(req), { code: "failed-precondition" });
  f.tick(600001);
  await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
  assert.equal(f.tokens.length, 0);
});
test("disabled, deleting and recreated accounts are rejected", async () => {
  for (const mode of ["disabled", "deleting", "recreated", "removed"]) {
    const f = fixture(); const sent = await f.start();
    if (mode === "disabled") f.setUser({ uid: "existing", disabled: true });
    if (mode === "deleting") f.setDeleted();
    if (mode === "recreated") f.setUser({ uid: "replacement" });
    if (mode === "removed") f.setUser(null);
    await assert.rejects(f.check(sent.verificationId));
    assert.equal(f.tokens.length, 0);
  }
});
test("concurrent verification is consumed exactly once", async () => {
  const f = fixture(); const sent = await f.start();
  let release;
  f.setHold(new Promise(resolve => { release = resolve; }));
  const one = f.check(sent.verificationId);
  await new Promise(resolve => setImmediate(resolve));
  await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
  release(); await one;
  assert.equal(f.tokens.length, 1);
});
test("ambiguous provider failure cannot later mint a token", async () => {
  const f = fixture(); const sent = await f.start();
  f.setError(new HttpsError("unavailable", "timeout"));
  await assert.rejects(f.check(sent.verificationId), { code: "unavailable" });
  f.setError(null);
  await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
  assert.equal(f.tokens.length, 0);
});
test("a mismatched provider verification never authenticates", async () => {
  const f = fixture(); const sent = await f.start();
  f.setResult({ success: true, verification: { id: "different" } });
  await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
  assert.equal(f.tokens.length, 0);
});

test("OTP proof cannot mint a token for the other account role", async () => {
  for (const [existing, requested] of [["passenger", "driver"], ["driver", "passenger"]]) {
    const f = fixture(); f.setRole(existing);
    const sent = await f.service.start(f.request({ phoneNumber: "+211922049035", role: requested }));
    await assert.rejects(f.check(sent.verificationId), { code: "failed-precondition" });
    assert.deepEqual(f.tokens, []);
    assert.equal(f.calls.filter(c => c.path === "/check").length, 1);
  }
});
test("matching account role continues to use its original UID", async () => {
  const f = fixture(); f.setRole("passenger");
  const sent = await f.start(); await f.check(sent.verificationId);
  assert.deepEqual(f.tokens, ["existing"]);
});
