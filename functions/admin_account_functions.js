"use strict";
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getDatabase } = require("firebase-admin/database");
const { logger } = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { createAdminAccountDeleter } = require("./admin_account_logic");
const removeAccount = createAdminAccountDeleter({ db: getFirestore(), auth: getAuth(),
  storage: getStorage(), realtimeDb: getDatabase(), HttpsError });
exports.adminDeleteAccount = onCall({ region: "africa-south1", timeoutSeconds: 120, memory: "256MiB" }, async (request) => {
  try { return await removeAccount(request); }
  catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("Account deletion incomplete", { uid: request.data?.uid, code: error.code, message: error.message });
    throw new HttpsError("internal", "Deletion did not finish. Retry the same account to safely complete cleanup.");
  }
});
