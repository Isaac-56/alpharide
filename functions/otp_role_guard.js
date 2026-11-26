"use strict";

const { hashPhoneNumber, inferExistingRole, roleConflictMessage } = require("./account_role_logic");

// Read-only login guard. Registration still claims a role transactionally via
// claimAccountRole, so abandoned OTP flows never reserve an account type.
function createOtpRoleGuard({ db, HttpsError }) {
  return async function assertRole(uid, phone, desiredRole) {
    const refs = [
      db.collection("account_roles").doc(uid),
      db.collection("identity_registry").doc(hashPhoneNumber(phone)),
      db.collection("users").doc(uid),
      db.collection("users").doc(phone),
      db.collection("drivers").doc(uid),
    ];
    return db.runTransaction(async tx => {
      const [role, identity, passenger, legacy, driver] = await tx.getAll(...refs);
      if (role.get("deletionPending") === true || role.get("deleted") === true)
        throw new HttpsError("failed-precondition", "This account is being reset. Try again after cleanup finishes.");
      let existing;
      try {
        existing = inferExistingRole({
          accountRole: role.get("role") ?? null,
          identityRole: identity.get("role") ?? null,
          passengerExists: passenger.exists,
          legacyPassengerExists: legacy.exists,
          driverExists: driver.exists,
        });
      } catch (error) {
        if (!(error instanceof RangeError || error instanceof TypeError)) throw error;
        throw new HttpsError("failed-precondition", "This phone number has conflicting Alpha account records. Contact support.");
      }
      if (existing && existing !== desiredRole)
        throw new HttpsError("failed-precondition", roleConflictMessage(existing, desiredRole));
    });
  };
}
module.exports = { createOtpRoleGuard };
