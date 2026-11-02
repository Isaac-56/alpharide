"use strict";
const { createHash } = require("node:crypto");
function createRequestSecurity({ db, auth, HttpsError, clock = Date.now }) {
  async function limit(uid, action = "callable", maximum = 240, windowMs = 60000) {
    const key = createHash("sha256").update(`${action}:${uid}`).digest("hex");
    const ref = db.collection("security_request_limits").doc(key);
    await db.runTransaction(async tx => {
      const saved = (await tx.get(ref)).data() || {};
      const now = clock();
      const active = Number.isFinite(saved.start) && now >= saved.start && now - saved.start < windowMs;
      const count = active ? Number(saved.count) || 0 : 0;
      if (count >= maximum) throw new HttpsError("resource-exhausted", "Too many requests. Wait a moment and try again.");
      tx.set(ref, { start: active ? saved.start : now, count: count + 1, expiresAt: new Date(now + windowMs * 2) });
    });
  }
  async function guard(request) {
    if (Buffer.byteLength(JSON.stringify(request.data ?? null), "utf8") > 32768) {
      throw new HttpsError("invalid-argument", "The request is too large.");
    }
    const uid = request.auth?.uid;
    // Preflight phone-role checks intentionally precede sign-in. Bound these
    // separately without persisting raw IP addresses or phone numbers.
    if (!uid) {
      const ip = request.rawRequest?.ip;
      if (typeof ip === "string" && ip) await limit(ip, "anonymous", 120, 600000);
      return;
    }
    let user;
    try { user = await auth.getUser(uid); }
    catch (error) {
      if (error.code === "auth/user-not-found") throw new HttpsError("unauthenticated", "Sign in again to continue.");
      throw error;
    }
    const validAfter = Date.parse(user.tokensValidAfterTime || "");
    const authenticatedAt = Number(request.auth.token?.auth_time);
    if (user.disabled || (Number.isFinite(validAfter) && (!Number.isFinite(authenticatedAt) || authenticatedAt < Math.floor(validAfter / 1000)))) {
      throw new HttpsError("unauthenticated", "This session has expired. Sign in again.");
    }
    const staff = request.auth.token?.admin === true || request.auth.token?.customerService === true;
    const phone = request.auth.token?.phone_number;
    if (!staff && (typeof phone !== "string" || !/^\+[1-9]\d{6,14}$/.test(phone) || phone !== user.phoneNumber)) {
      throw new HttpsError("permission-denied", "A verified phone account is required.");
    }
    const account = await db.collection("account_roles").doc(uid).get();
    if (account.get("deletionPending") === true || account.get("deleted") === true) {
      throw new HttpsError("permission-denied", "This account is no longer active.");
    }
    await limit(uid);
  }
  return { guard, limit };
}
module.exports = { createRequestSecurity };
