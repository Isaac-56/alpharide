"use strict";

const { getAuth } = require("firebase-admin/auth");
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

const auth = getAuth();
const db = getFirestore();
const REGION = "africa-south1";

async function userIdForPhoneNumber(phoneNumber) {
  try {
    const user = await auth.getUserByPhoneNumber(phoneNumber);
    return user.uid;
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      return null;
    }

    throw error;
  }
}

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

  // Firebase Authentication is the canonical phone-to-UID directory. Older
  // Alpha accounts may not have a normalized phoneNumber field or role index,
  // so resolving the UID first lets preflight inspect their real profile before
  // an SMS is sent.
  const uidPromise = userIdForPhoneNumber(phoneNumber);
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

  // Independent legacy/index reads run while Auth resolves the UID.
  // Attach all rejection handlers immediately so neither branch is orphaned.
  const [indexedSnapshots, directSnapshots] = await Promise.all([
    Promise.all([
      identityRef.get(), accountRoleQuery.get(), legacyPassengerRef.get(),
      passengerQuery.get(), driverQuery.get(),
    ]),
    uidPromise.then((uid) => uid
      ? db.getAll(
        db.collection("account_roles").doc(uid),
        db.collection("users").doc(uid),
        db.collection("drivers").doc(uid),
      )
      : [null, null, null]),
  ]);
  const [identitySnapshot, accountRoleSnapshot, legacyPassengerSnapshot,
    passengerSnapshot, driverSnapshot] = indexedSnapshots;
  const [directAccountRoleSnapshot, directPassengerSnapshot,
    directDriverSnapshot] = directSnapshots;

  const registryRoles = new Set();
  const addRegistryRole = (value) => {
    if (value == null || value === "") return;
    registryRoles.add(normalizeAccountRole(value));
  };

  addRegistryRole(identitySnapshot.data()?.role);
  addRegistryRole(directAccountRoleSnapshot?.data()?.role);
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
    passengerExists:
      (directPassengerSnapshot?.exists ?? false) || !passengerSnapshot.empty,
    legacyPassengerExists:
      legacyPassengerRef.path !== directPassengerSnapshot?.ref.path &&
      legacyPassengerSnapshot.exists,
    driverExists:
      (directDriverSnapshot?.exists ?? false) || !driverSnapshot.empty,
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
    // One transactional batch replaces five sequential network round trips.
    const [accountRoleSnapshot, identitySnapshot, passengerSnapshot,
      legacyPassengerSnapshot, driverSnapshot] = await transaction.getAll(
      accountRoleRef, identityRef, passengerRef, legacyPassengerRef, driverRef,
    );

    if (accountRoleSnapshot.data()?.deletionPending === true) {
      throw new HttpsError("failed-precondition", "This account is being deleted. Sign in again after cleanup completes.");
    }
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

    // Existing correct claims need no writes on every login/profile check.
    if (accountRoleSnapshot.data()?.role !== resolvedRole ||
        accountRoleSnapshot.data()?.phoneHash !== phoneHash) {
      transaction.set(accountRoleRef, accountRoleData, { merge: true });
    }
    if (identitySnapshot.data()?.role !== resolvedRole ||
        identitySnapshot.data()?.uid !== uid) {
      transaction.set(identityRef, identityData, { merge: true });
    }
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


