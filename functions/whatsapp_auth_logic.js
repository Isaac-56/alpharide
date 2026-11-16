"use strict";

const { createHash, randomBytes } = require("node:crypto");
const hash = value => createHash("sha256").update(value).digest("hex");
const MINUTE = 60000;

// All persisted state is server-only. Never store a passcode or custom token.
function createWhatsAppAuth({ store, limit, provider, auth, HttpsError,
  clock = Date.now, random = () => randomBytes(32).toString("hex") }) {
  const fail = (code, message) => new HttpsError(code, message);
  function context(request) {
    if (!request.app?.appId) throw fail("unauthenticated", "App verification failed. Update the app and try again.");
    if (Buffer.byteLength(JSON.stringify(request.data ?? {})) > 2048)
      throw fail("invalid-argument", "Invalid verification request.");
    return { appId: request.app.appId, ip: request.rawRequest?.ip || "unknown" };
  }
  async function findUser(phone) {
    try { return await auth.getUserByPhoneNumber(phone); }
    catch (e) { if (e.code === "auth/user-not-found") return null; throw e; }
  }
  async function usable(user) {
    if (user?.disabled) throw fail("permission-denied", "This account is unavailable. Contact support.");
    if (user && await store.isDeleted(user.uid))
      throw fail("permission-denied", "This account is being reset. Try again after cleanup finishes.");
  }
  async function start(request) {
    const { appId, ip } = context(request);
    const phone = request.data?.phoneNumber;
    const role = request.data?.role;
    if (typeof phone !== "string" || !/^\+211[1-9]\d{8}$/.test(phone))
      throw fail("invalid-argument", "Use +211 followed by your nine-digit WhatsApp number.");
    if (!["passenger", "driver"].includes(role))
      throw fail("invalid-argument", "Invalid app.");
    const key = hash(phone);
    await limit(ip, "whatsapp-send-ip", 10, 60 * MINUTE);
    await limit(key, "whatsapp-send-phone", 5, 60 * MINUTE);
    // Initial rollout budget. Increase deliberately after observing real traffic.
    await limit("all", "whatsapp-send-global", 500, 24 * 60 * MINUTE);
    const before = await findUser(phone);
    // Avoid disclosing account status before ownership is proved.
    const nonce = random();
    const now = clock();
    await store.mutate(key, state => {
      if ((state.lockUntil || 0) > now || (state.nextSendAt || 0) > now)
        throw fail("resource-exhausted", "Wait 60 seconds before requesting another code.");
      return {
        phone, role, appId, nonceHash: hash(nonce), uidAtSend: before?.uid ?? null,
        state: "sending", attempts: 0, lockUntil: now + MINUTE,
        nextSendAt: now + MINUTE, expiresAtMs: now + 10 * MINUTE,
        deleteAfter: new Date(now + 24 * 60 * MINUTE),
      };
    });
    try {
      const sent = await provider("", {
        to: { phone_number: phone },
        options: { channels: ["whatsapp"], language: "en" },
      });
      const expires = Date.parse(sent.expires_at);
      if (sent.status !== "pending" || sent.last_channel !== "whatsapp" ||
          !Number.isFinite(expires) || expires <= clock() || typeof sent.id !== "string")
        throw fail("unavailable", "WhatsApp could not send a code. Try again later.");
      await store.mutate(key, state => {
        if (state.nonceHash !== hash(nonce) || state.state !== "sending")
          throw fail("aborted", "Request a new code.");
        return { ...state, providerId: sent.id, state: "pending", lockUntil: 0,
          expiresAtMs: Math.min(expires, state.expiresAtMs) };
      });
      return { verificationId: key + "." + nonce, resendAfterSeconds: 60 };
    } catch (e) {
      await store.mutate(key, state => state.nonceHash === hash(nonce)
        ? { ...state, state: "failed", lockUntil: 0 } : state);
      throw e;
    }
  }
  async function check(request) {
    const { appId, ip } = context(request);
    const id = request.data?.verificationId;
    const code = request.data?.code;
    if (typeof id !== "string" || !/^[a-f0-9]{64}\.[a-f0-9]{64}$/.test(id) ||
        typeof code !== "string" || !/^\d{6}$/.test(code))
      throw fail("invalid-argument", "Enter the six-digit code from WhatsApp.");
    await limit(ip, "whatsapp-check-ip", 30, 10 * MINUTE);
    const [key, nonce] = id.split(".");
    let challenge;
    await store.mutate(key, state => {
      if (state.nonceHash !== hash(nonce) || state.appId !== appId ||
          state.state !== "pending" || state.expiresAtMs <= clock())
        throw fail("failed-precondition", "This code session expired or was replaced. Request a new code.");
      if (state.attempts >= 5)
        throw fail("resource-exhausted", "Too many incorrect codes. Request a new code.");
      challenge = { ...state, attempts: state.attempts + 1, state: "checking",
        lockUntil: clock() + MINUTE };
      return challenge;
    });
    let checked;
    try {
      checked = await provider("/check", { to: { phone_number: challenge.phone }, code });
    } catch (e) {
      // The provider may have consumed the OTP even if the response was lost.
      // Never retry an ambiguous successful check or mint from cached success.
      await store.mutate(key, state => state.nonceHash === hash(nonce)
        ? { ...state, state: "failed", lockUntil: 0 } : state);
      throw e;
    }
    let accepted = false;
    await store.mutate(key, state => {
      if (state.nonceHash !== hash(nonce) || state.state !== "checking" ||
          state.expiresAtMs <= clock())
        throw fail("failed-precondition", "This code session expired. Request a new code.");
      accepted = checked.success === true &&
        (!checked.verification || checked.verification.id === state.providerId);
      return { ...state, lockUntil: 0,
        state: accepted ? "consumed"
          : checked.reason === "incorrect_code" && state.attempts < 5 ? "pending" : "failed" };
    });
    if (!accepted) {
      if (checked.reason === "incorrect_code")
        throw fail("invalid-argument", "That WhatsApp code is incorrect. Try again.");
      throw fail("failed-precondition", "This code expired or cannot be used. Request a new code.");
    }
    let user = await findUser(challenge.phone);
    // An admin reset while a code is outstanding must invalidate that login.
    if ((user?.uid ?? null) !== challenge.uidAtSend)
      throw fail("failed-precondition", "Your account changed. Request a new code.");
    await usable(user);
    if (!user) {
      try { user = await auth.createUser({ phoneNumber: challenge.phone }); }
      catch (e) {
        if (e.code === "auth/phone-number-already-exists")
          throw fail("failed-precondition", "Your account changed. Request a new code.");
        throw e;
      }
    }
    await usable(user);
    // Auth's canonical phone record preserves the UID and ID-token phone claim.
    // Existing role/session checks still run in the client after Firebase login.
    const customToken = await auth.createCustomToken(user.uid);
    return { customToken };
  }
  return { start, check };
}
module.exports = { createWhatsAppAuth };
