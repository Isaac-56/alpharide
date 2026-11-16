"use strict";

const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");
const { createRequestSecurity } = require("./request_security_logic");
const { createWhatsAppAuth } = require("./whatsapp_auth_logic");
const birdKey = defineSecret("BIRD_API_KEY");
const db = getFirestore();
const auth = getAuth();
const security = createRequestSecurity({ db, auth, HttpsError });
const store = {
  async mutate(key, change) {
    const ref = db.collection("whatsapp_auth_challenges").doc(key);
    return db.runTransaction(async tx => {
      const old = (await tx.get(ref)).data() || {};
      tx.set(ref, change(old));
    });
  },
  async isDeleted(uid) {
    const doc = await db.collection("account_roles").doc(uid).get();
    return doc.get("deletionPending") === true || doc.get("deleted") === true;
  },
};
async function provider(path, body) {
  let response;
  try {
    response = await fetch("https://eu1.platform.bird.com/v1/verify/verifications" + path, {
      method: "POST",
      headers: { Authorization: "Bearer " + birdKey.value().trim(), "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
  } catch (_) {
    throw new HttpsError("unavailable", "WhatsApp verification could not be reached. Request a new code shortly.");
  }
  if (!response.ok) {
    // Do not log the provider body, recipient, credentials or OTP.
    logger.warn("whatsapp_auth_provider_failure", { status: response.status, operation: path ? "check" : "send" });
    if (response.status === 429)
      throw new HttpsError("resource-exhausted", "Too many requests. Wait before trying again.");
    if (path && response.status === 404)
      throw new HttpsError("failed-precondition", "This code expired. Request a new code.");
    throw new HttpsError("unavailable", "WhatsApp verification is temporarily unavailable. Try again later.");
  }
  try { return await response.json(); }
  catch (_) { throw new HttpsError("unavailable", "Unable to confirm verification. Request a new code."); }
}
const service = createWhatsAppAuth({ store, limit: security.limit, provider, auth, HttpsError });
function callable(handler) {
  // Paid anonymous endpoints require App Check independently of the legacy
  // ALPHA_ENFORCE_APP_CHECK rollout parameter. Never disable this for testing.
  return onCall({
    region: "africa-south1", secrets: [birdKey], enforceAppCheck: true,
    timeoutSeconds: 60, memory: "256MiB", maxInstances: 10,
  }, async request => {
    try { return await handler(request); }
    catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("whatsapp_auth_internal_failure", { code: e.code || "unknown" });
      throw new HttpsError("internal", "Unable to complete sign-in. Request a new code and try again.");
    }
  });
}
exports.requestWhatsAppOtp = callable(service.start);
exports.verifyWhatsAppOtp = callable(service.check);
