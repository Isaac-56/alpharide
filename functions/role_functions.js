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
  normalizePhoneNumber,
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

async function evaluateAccountRolePreflight(request) {
  const desiredRole = normalizeAccountRole(request.data?.role);
  const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);
  const phoneHash = hashPhoneNumber(phoneNumber);

  const identityRef = db.collection("identity_registry").doc(phoneHash);
  const accountRoleQuery = db
    .collection("account_roles")
    .where("phoneHash", "==", phoneHash)
    .limit(2);
  const legacyPassengerRef = db.collection("users").doc(phoneNumber);
  const passengerQuery = db
    .collection("users")
    .where("phoneNumber", "==", phoneNumber)
    .limit(1);
  const driverQuery = db
    .collection("drivers")
    .where("phoneNumber", "==", phoneNumber)
    .limit(1);

  const [
    identitySnapshot,
    accountRoleSnapshot,
    legacyPassengerSnapshot,
    passengerSnapshot,
    driverSnapshot,
  ] = await Promise.all([
    identityRef.get(),
    accountRoleQuery.get(),
    legacyPassengerRef.get(),
    passengerQuery.get(),
    driverQuery.get(),
  ]);

  const registryRoles = new Set();
  const addRegistryRole = (value) => {
    if (value == null || value === "") return;
    registryRoles.add(normalizeAccountRole(value));
  };

  addRegistryRole(identitySnapshot.data()?.role);
  for (const document of accountRoleSnapshot.docs) {
    addRegistryRole(document.data()?.role);
  }

  if (registryRoles.size > 1) {
    throw new RangeError(
      "Conflicting passenger and driver account records already exist.",
    );
  }

  const existingRole = inferExistingRole({
    accountRole: registryRoles.size === 1 ? [...registryRoles][0] : null,
    passengerExists: !passengerSnapshot.empty,
    legacyPassengerExists: legacyPassengerSnapshot.exists,
    driverExists: !driverSnapshot.empty,
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

  return {
    eligible: true,
    registered: existingRole != null,
  };
}

async function evaluateAccountRole(request, { claimIfUnassigned }) {
  const { uid, phoneNumber } = authenticatedIdentity(request);
  const desiredRole = normalizeAccountRole(request.data?.role);
  const phoneHash = hashPhoneNumber(phoneNumber);

  const accountRoleRef = db.collection("account_roles").doc(uid);
  const identityRef = db.collection("identity_registry").doc(phoneHash);
  const passengerRef = db.collection("users").doc(uid);
  const legacyPassengerRef = db.collection("users").doc(phoneNumber);
  const driverRef = db.collection("drivers").doc(uid);

  let resolvedRole = null;
  let claimed = false;
  let migrated = false;

  await db.runTransaction(async (transaction) => {
    const accountRoleSnapshot = await transaction.get(accountRoleRef);
    const identitySnapshot = await transaction.get(identityRef);
    const passengerSnapshot = await transaction.get(passengerRef);
    const legacyPassengerSnapshot = await transaction.get(legacyPassengerRef);
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

    resolvedRole = existingRole ?? (claimIfUnassigned ? desiredRole : null);
    claimed = resolvedRole != null;

    if (resolvedRole == null) {
      return;
    }

    migrated =
      existingRole != null &&
      (!accountRoleSnapshot.exists || !identitySnapshot.exists);

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
    eligible: true,
    claimed,
    migrated,
  };
}

function roleCallable(claimIfUnassigned) {
  return onCall(
    {
      region: REGION,
      timeoutSeconds: 15,
      memory: "256MiB",
    },
    async (request) => {
      try {
        return await evaluateAccountRole(request, { claimIfUnassigned });
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

        logger.error("Unable to evaluate Alpha account role", error);
        throw new HttpsError(
          "internal",
          "Unable to confirm this Alpha account right now. Please try again.",
        );
      }
    },
  );
}

// Runs before Firebase sends an SMS. It is read-only and only rejects a phone
// already assigned to the other Alpha product. The authenticated claim below
// remains authoritative so a modified client cannot bypass role enforcement.
exports.preflightAccountRole = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      return await evaluateAccountRolePreflight(request);
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

      logger.error("Unable to preflight Alpha account role", error);
      throw new HttpsError(
        "internal",
        "Unable to confirm this Alpha account right now. Please try again.",
      );
    }
  },
);

// Checks whether the signed-in phone may use the requested app. For a brand-new
// phone it does not reserve a role, so abandoning OTP/onboarding cannot lock the
// person into an app they never actually registered for. Existing legacy
// profiles are lazily migrated into the role registry here.
exports.checkAccountRole = roleCallable(false);

// Called immediately before the first passenger/driver profile is created.
// This is the authoritative, transactional "first completed registration wins"
// operation used by both apps.
exports.claimAccountRole = roleCallable(true);
