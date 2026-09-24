"use strict";

const { getAuth } = require("firebase-admin/auth");
const {
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const { normalizePhoneNumber } = require("./account_role_logic");
const { PLATFORM_COMMISSION_BPS } = require("./accounting_logic");
const {
  effectiveVehicleClassForProfile,
  fixedVehicleClassForBody,
  requireAdminVehicleClass,
  requiresAdminVehicleClass,
} = require("./vehicle_logic");
const {
  DEFAULT_LOW_BALANCE_THRESHOLD,
  WALLET_SCHEMA_VERSION,
  applyWalletCredit,
  normalizeTopUpAmount,
  normalizeWalletStatus,
  walletState,
} = require("./wallet_logic");

const REGION = "africa-south1";
const auth = getAuth();
const db = getFirestore();

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before using the wallet.");
  }
  return uid;
}

function requireAdmin(request) {
  const uid = requireUid(request);
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "An authorized Alpha administrator account is required.",
    );
  }
  return {
    uid,
    email:
      typeof request.auth?.token?.email === "string"
        ? request.auth.token.email
        : "",
  };
}

function walletReference(driverId) {
  return db.collection("driver_wallets").doc(driverId);
}

function walletPayload(driverId, data = {}) {
  const state = walletState(data);
  return {
    driverId,
    ...state,
    lifetimeCredits: Number.isInteger(data?.lifetimeCredits)
      ? data.lifetimeCredits
      : 0,
    lifetimeDebits: Number.isInteger(data?.lifetimeDebits)
      ? data.lifetimeDebits
      : 0,
    lastTransactionType:
      typeof data?.lastTransactionType === "string"
        ? data.lastTransactionType
        : null,
    lastTransactionAtMillis:
      typeof data?.lastTransactionAt?.toMillis === "function"
        ? data.lastTransactionAt.toMillis()
        : null,
  };
}

function newWalletDocument(driverId, now) {
  return {
    schemaVersion: WALLET_SCHEMA_VERSION,
    driverId,
    currencyCode: "SSP",
    balance: 0,
    status: "active",
    lowBalanceThreshold: DEFAULT_LOW_BALANCE_THRESHOLD,
    isLowBalance: true,
    canGoOnline: false,
    lifetimeCredits: 0,
    lifetimeDebits: 0,
    createdAt: now,
    updatedAt: now,
  };
}

async function ensureWallet(driverId) {
  const ref = walletReference(driverId);
  let result;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.exists) {
      result = walletPayload(driverId, snapshot.data());
      return;
    }

    const now = FieldValue.serverTimestamp();
    const data = newWalletDocument(driverId, now);
    transaction.create(ref, data);
    result = walletPayload(driverId, data);
  });

  return result;
}

function cleanText(value, fieldName, maxLength) {
  if (value == null) return "";
  if (typeof value !== "string") {
    throw new TypeError(`${fieldName} must be text`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new RangeError(`${fieldName} is too long`);
  }
  return normalized;
}

function cleanDriverId(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new TypeError("driverId is required");
  }
  const normalized = value.trim();
  if (normalized.length > 128 || normalized.includes("/")) {
    throw new RangeError("driverId is invalid");
  }
  return normalized;
}

async function resolveDriverId(data) {
  if (typeof data?.driverId === "string" && data.driverId.trim()) {
    return cleanDriverId(data.driverId);
  }

  const phoneNumber = normalizePhoneNumber(data?.phoneNumber);
  try {
    return (await auth.getUserByPhoneNumber(phoneNumber)).uid;
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      throw new HttpsError(
        "not-found",
        "No Alpha account uses that phone number.",
      );
    }
    throw error;
  }
}

function callable(handler, fallbackMessage) {
  return onCall(
    {
      region: REGION,
      timeoutSeconds: 20,
      memory: "256MiB",
    },
    async (request) => {
      try {
        return await handler(request);
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        if (error instanceof TypeError) {
          throw new HttpsError("invalid-argument", error.message);
        }
        if (error instanceof RangeError) {
          throw new HttpsError("failed-precondition", error.message);
        }
        logger.error(fallbackMessage, error);
        throw new HttpsError("internal", fallbackMessage);
      }
    },
  );
}

exports.getDriverWallet = callable(async (request) => {
  const driverId = requireUid(request);
  return ensureWallet(driverId);
}, "The driver wallet could not be loaded.");

exports.checkDriverWalletEligibility = callable(async (request) => {
  const driverId = requireUid(request);
  const wallet = await ensureWallet(driverId);

  if (wallet.status !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "Your driver wallet is suspended. Contact the Alpha office.",
      { reason: "wallet_suspended", wallet },
    );
  }
  if (wallet.balance <= 0) {
    throw new HttpsError(
      "failed-precondition",
      "Recharge your Alpha wallet at the office before going online.",
      { reason: "wallet_empty", wallet },
    );
  }

  return wallet;
}, "Alpha Plus could not confirm the wallet balance.");

exports.adminListDrivers = callable(async (request) => {
  requireAdmin(request);
  const rawLimit = request.data?.limit;
  const limit = Number.isInteger(rawLimit)
    ? Math.min(Math.max(rawLimit, 1), 100)
    : 50;
  const driverSnapshot = await db.collection("drivers").limit(limit).get();

  const drivers = await Promise.all(
    driverSnapshot.docs.map(async (document) => {
      const profile = document.data();
      const walletSnapshot = await walletReference(document.id).get();
      const registration =
        profile?.registration && typeof profile.registration === "object"
          ? profile.registration
          : {};
      const profileWithRegistration = { ...profile, registration };
      const vehicleClass =
        effectiveVehicleClassForProfile(profileWithRegistration);
      return {
        driverId: document.id,
        firstName:
          typeof profile?.firstName === "string" ? profile.firstName : "",
        lastName:
          typeof profile?.lastName === "string" ? profile.lastName : "",
        phoneNumber:
          typeof profile?.phoneNumber === "string" ? profile.phoneNumber : "",
        reviewStatus:
          typeof profile?.reviewStatus === "string"
            ? profile.reviewStatus
            : "pending",
        vehicleType:
          typeof registration?.vehicleType === "string"
            ? registration.vehicleType
            : "",
        vehicleClass,
        requiresVehicleClass:
          requiresAdminVehicleClass(profileWithRegistration) &&
          vehicleClass === "",
        plateNumber:
          typeof registration?.plateNumber === "string"
            ? registration.plateNumber
            : "",
        wallet: walletPayload(
          document.id,
          walletSnapshot.exists ? walletSnapshot.data() : {},
        ),
      };
    }),
  );

  drivers.sort((first, second) => {
    const firstName = `${first.firstName} ${first.lastName}`.trim();
    const secondName = `${second.firstName} ${second.lastName}`.trim();
    return firstName.localeCompare(secondName);
  });

  return { drivers };
}, "The driver directory could not be loaded.");

exports.adminCreditDriverWallet = callable(async (request) => {
  const administrator = requireAdmin(request);
  const driverId = await resolveDriverId(request.data);
  const amount = normalizeTopUpAmount(request.data?.amount);
  const reference = cleanText(request.data?.reference, "reference", 80);
  const note = cleanText(request.data?.note, "note", 240);
  const profileRef = db.collection("drivers").doc(driverId);
  const walletRef = walletReference(driverId);
  const transactionRef = walletRef.collection("transactions").doc();
  let response;

  await db.runTransaction(async (transaction) => {
    const [profileSnapshot, walletSnapshot] = await Promise.all([
      transaction.get(profileRef),
      transaction.get(walletRef),
    ]);
    if (!profileSnapshot.exists) {
      throw new HttpsError(
        "not-found",
        "This account does not have an Alpha Plus driver profile.",
      );
    }

    const before = walletState(walletSnapshot.exists ? walletSnapshot.data() : {});
    const after = applyWalletCredit({ wallet: before, amount });
    const now = FieldValue.serverTimestamp();
    const walletData = {
      schemaVersion: WALLET_SCHEMA_VERSION,
      driverId,
      currencyCode: "SSP",
      balance: after.balance,
      status: after.status,
      lowBalanceThreshold: after.lowBalanceThreshold,
      isLowBalance: after.isLowBalance,
      canGoOnline: after.canGoOnline,
      lifetimeCredits: FieldValue.increment(amount),
      lifetimeDebits: walletSnapshot.exists
        ? walletSnapshot.get("lifetimeDebits") ?? 0
        : 0,
      lastTransactionType: "top_up",
      lastTransactionAt: now,
      updatedAt: now,
    };
    if (!walletSnapshot.exists) {
      walletData.createdAt = now;
    }

    transaction.set(walletRef, walletData, { merge: true });
    transaction.create(transactionRef, {
      schemaVersion: 1,
      driverId,
      type: "top_up",
      amount,
      balanceBefore: before.balance,
      balanceAfter: after.balance,
      currencyCode: "SSP",
      reference,
      note,
      administratorUid: administrator.uid,
      administratorEmail: administrator.email,
      createdAt: now,
    });
    response = walletPayload(driverId, {
      ...walletData,
      lifetimeCredits:
        (walletSnapshot.exists
          ? walletSnapshot.get("lifetimeCredits") ?? 0
          : 0) + amount,
    });
  });

  return {
    wallet: response,
    transactionId: transactionRef.id,
  };
}, "The wallet recharge could not be completed.");

exports.adminSetDriverWalletStatus = callable(async (request) => {
  const administrator = requireAdmin(request);
  const driverId = await resolveDriverId(request.data);
  const status = normalizeWalletStatus(request.data?.status);
  const note = cleanText(request.data?.note, "note", 240);
  const walletRef = walletReference(driverId);
  const transactionRef = walletRef.collection("transactions").doc();
  let response;

  await db.runTransaction(async (transaction) => {
    const walletSnapshot = await transaction.get(walletRef);
    const before = walletState(walletSnapshot.exists ? walletSnapshot.data() : {});
    const after = walletState({ ...before, status });
    const now = FieldValue.serverTimestamp();
    const walletData = {
      schemaVersion: WALLET_SCHEMA_VERSION,
      driverId,
      currencyCode: "SSP",
      balance: after.balance,
      status: after.status,
      lowBalanceThreshold: after.lowBalanceThreshold,
      isLowBalance: after.isLowBalance,
      canGoOnline: after.canGoOnline,
      lifetimeCredits: walletSnapshot.exists
        ? walletSnapshot.get("lifetimeCredits") ?? 0
        : 0,
      lifetimeDebits: walletSnapshot.exists
        ? walletSnapshot.get("lifetimeDebits") ?? 0
        : 0,
      lastTransactionType: "status_change",
      lastTransactionAt: now,
      updatedAt: now,
    };
    if (!walletSnapshot.exists) walletData.createdAt = now;

    transaction.set(walletRef, walletData, { merge: true });
    transaction.create(transactionRef, {
      schemaVersion: 1,
      driverId,
      type: "status_change",
      amount: 0,
      balanceBefore: before.balance,
      balanceAfter: after.balance,
      previousStatus: before.status,
      status: after.status,
      currencyCode: "SSP",
      note,
      administratorUid: administrator.uid,
      administratorEmail: administrator.email,
      createdAt: now,
    });
    response = walletPayload(driverId, walletData);
  });

  return { wallet: response };
}, "The wallet status could not be updated.");

exports.adminSetDriverVehicleClass = callable(async (request) => {
  const administrator = requireAdmin(request);
  const driverId = await resolveDriverId(request.data);
  const vehicleClass = requireAdminVehicleClass(request.data?.vehicleClass);
  const profileRef = db.collection("drivers").doc(driverId);
  const auditRef = db.collection("admin_audit_log").doc();

  await db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(profileRef);
    if (!profileSnapshot.exists) {
      throw new HttpsError("not-found", "Driver profile not found.");
    }

    const profile = profileSnapshot.data();
    const registration =
      profile?.registration && typeof profile.registration === "object"
        ? profile.registration
        : {};
    const fixedClass = fixedVehicleClassForBody(registration.vehicleType);
    if (fixedClass) {
      throw new HttpsError(
        "failed-precondition",
        `This vehicle is automatically classified as ${fixedClass}.`,
      );
    }
    if (!requiresAdminVehicleClass(profile)) {
      throw new HttpsError(
        "failed-precondition",
        "A supported regular vehicle category is required first.",
      );
    }

    const previousVehicleClass =
      effectiveVehicleClassForProfile(profile) || null;
    const now = FieldValue.serverTimestamp();
    transaction.update(profileRef, {
      "registration.vehicleClass": vehicleClass,
      vehicleClass,
      vehicleClassAssignedAt: now,
      vehicleClassAssignedBy: administrator.uid,
      updatedAt: now,
    });
    transaction.create(auditRef, {
      action: "driver_vehicle_class",
      driverId,
      previousVehicleClass,
      vehicleClass,
      administratorUid: administrator.uid,
      administratorEmail: administrator.email,
      createdAt: now,
    });
  });

  return { driverId, vehicleClass };
}, "The driver vehicle class could not be updated.");

exports.adminSetDriverReviewStatus = callable(async (request) => {
  const administrator = requireAdmin(request);
  const driverId = await resolveDriverId(request.data);
  const reviewStatus =
    typeof request.data?.reviewStatus === "string"
      ? request.data.reviewStatus.trim().toLowerCase()
      : "";
  if (!["pending", "approved", "rejected"].includes(reviewStatus)) {
    throw new TypeError("reviewStatus must be pending, approved or rejected");
  }
  const note = cleanText(request.data?.note, "note", 240);
  const profileRef = db.collection("drivers").doc(driverId);
  const auditRef = db.collection("admin_audit_log").doc();

  await db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(profileRef);
    if (!profileSnapshot.exists) {
      throw new HttpsError("not-found", "Driver profile not found.");
    }
    const profile = profileSnapshot.data();
    if (
      reviewStatus === "approved" &&
      !effectiveVehicleClassForProfile(profile)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Assign this regular vehicle to an Alpha ride class before approval.",
      );
    }

    const previousStatus = profileSnapshot.get("reviewStatus") ?? "pending";
    const now = FieldValue.serverTimestamp();
    transaction.update(profileRef, {
      reviewStatus,
      reviewNote: note,
      reviewedAt: now,
      reviewedBy: administrator.uid,
      updatedAt: now,
    });
    transaction.create(auditRef, {
      action: "driver_review_status",
      driverId,
      previousStatus,
      reviewStatus,
      note,
      administratorUid: administrator.uid,
      administratorEmail: administrator.email,
      createdAt: now,
    });
  });

  return { driverId, reviewStatus };
}, "The driver review status could not be updated.");

exports.adminListWalletTransactions = callable(async (request) => {
  requireAdmin(request);
  const driverId = await resolveDriverId(request.data);
  const snapshot = await walletReference(driverId)
    .collection("transactions")
    .orderBy("createdAt", "desc")
    .limit(100)
    .get();

  return {
    driverId,
    transactions: snapshot.docs.map((document) => {
      const data = document.data();
      return {
        transactionId: document.id,
        type: data.type ?? "",
        amount: data.amount ?? 0,
        balanceBefore: data.balanceBefore ?? 0,
        balanceAfter: data.balanceAfter ?? 0,
        currencyCode: data.currencyCode ?? "SSP",
        reference: data.reference ?? "",
        note: data.note ?? "",
        rideId: data.rideId ?? null,
        administratorEmail: data.administratorEmail ?? "",
        createdAtMillis:
          typeof data.createdAt?.toMillis === "function"
            ? data.createdAt.toMillis()
            : null,
      };
    }),
  };
}, "The wallet history could not be loaded.");

module.exports.walletPayload = walletPayload;
