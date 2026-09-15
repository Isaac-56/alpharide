"use strict";

const {
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const {
  hashPhoneNumber,
  inferExistingRole,
  normalizeAccountRole,
  roleConflictMessage,
} = require("./account_role_logic");

const db = getFirestore();
const REGION = "africa-south1";

function authenticatedIdentity(request) {
  const uid = request.auth?.uid;
  const phoneNumber = request.auth?.token?.phone_number;

  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in before registering an Alpha account.",
    );
  }

  if (typeof phoneNumber !== "string" || !phoneNumber.trim()) {
    throw new HttpsError(
      "failed-precondition",
      "A verified phone number is required before registration.",
    );
  }

  return {
    uid,
    phoneNumber: phoneNumber.trim(),
  };
}

exports.claimAccountRole = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const { uid, phoneNumber } = authenticatedIdentity(request);
      const desiredRole = normalizeAccountRole(request.data?.role);
      const phoneHash = hashPhoneNumber(phoneNumber);

      const accountRoleRef = db.collection("account_roles").doc(uid);
      const identityRef = db.collection("identity_registry").doc(phoneHash);
      const passengerRef = db.collection("users").doc(uid);
      const legacyPassengerRef = db.collection("users").doc(phoneNumber);
      const driverRef = db.collection("drivers").doc(uid);

      let resolvedRole = null;
      let migrated = false;

      await db.runTransaction(async (transaction) => {
        const accountRoleSnapshot = await transaction.get(accountRoleRef);
        const identitySnapshot = await transaction.get(identityRef);
        const passengerSnapshot = await transaction.get(passengerRef);
        const legacyPassengerSnapshot = await transaction.get(
          legacyPassengerRef,
        );
        const driverSnapshot = await transaction.get(driverRef);

        const existingRole = inferExistingRole({
          accountRole: accountRoleSnapshot.data()?.role ?? null,
          identityRole: identitySnapshot.data()?.role ?? null,
          passengerExists: passengerSnapshot.exists,
          legacyPassengerExists:
            legacyPassengerRef.path !== passengerRef.path &&
            legacyPassengerSnapshot.exists,
          driverExists: driverSnapshot.exists,
        });

        if (existingRole != null && existingRole !== desiredRole) {
          throw new HttpsError(
            "failed-precondition",
            roleConflictMessage(existingRole, desiredRole),
            {
              existingRole,
              desiredRole,
            },
          );
        }

        resolvedRole = existingRole ?? desiredRole;
        migrated = existingRole != null;

        const now = FieldValue.serverTimestamp();
        const accountRoleData = {
          role: resolvedRole,
          phoneHash,
          updatedAt: now,
        };
        if (!accountRoleSnapshot.exists) {
          accountRoleData.createdAt = now;
        }

        const identityData = {
          role: resolvedRole,
          uid,
          updatedAt: now,
        };
        if (!identitySnapshot.exists) {
          identityData.createdAt = now;
        }

        transaction.set(accountRoleRef, accountRoleData, { merge: true });
        transaction.set(identityRef, identityData, { merge: true });
      });

      return {
        role: resolvedRole,
        claimed: true,
        migrated,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      if (error instanceof TypeError) {
        throw new HttpsError("invalid-argument", error.message);
      }

      if (error instanceof RangeError) {
        logger.error("Conflicting Alpha account-role records", error);
        throw new HttpsError(
          "failed-precondition",
          "This phone number has conflicting Alpha account records. Contact support before continuing.",
        );
      }

      logger.error("Unable to claim Alpha account role", error);
      throw new HttpsError(
        "internal",
        "Unable to confirm this Alpha account right now. Please try again.",
      );
    }
  },
);
