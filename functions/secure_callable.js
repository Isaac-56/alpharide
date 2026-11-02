"use strict";
const { onCall: firebaseOnCall, HttpsError } = require("firebase-functions/v2/https");
const { defineBoolean } = require("firebase-functions/params");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { createRequestSecurity } = require("./request_security_logic");
// Roll out attestation clients before enabling enforcement. This parameter is
// evaluated by Firebase at deployment, never controlled by an APK/request.
const enforceAppCheck = defineBoolean("ALPHA_ENFORCE_APP_CHECK", { default: false });
let security;
function requestSecurity() {
  security ||= createRequestSecurity({ db: getFirestore(), auth: getAuth(), HttpsError });
  return security;
}
function onCall(options, handler) {
  return firebaseOnCall({ ...options, enforceAppCheck }, async request => {
    await requestSecurity().guard(request);
    return handler(request);
  });
}
module.exports = { onCall, requestSecurity };
