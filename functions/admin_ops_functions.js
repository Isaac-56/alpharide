"use strict";

const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const REGION = "africa-south1";
const ACTIVE_RIDE_STATUSES = [
  "requested",
  "offered",
  "accepted",
  "driver_arriving",
  "arrived",
  "in_progress",
];
const db = getFirestore();

function requireAdmin(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in to Alpha Admin first.");
  }
  if (request.auth.token?.admin !== true) {
    throw new HttpsError(
      "permission-denied",
      "An authorized Alpha administrator account is required.",
    );
  }
}

function callable(handler, fallbackMessage) {
  return onCall(
    { region: REGION, timeoutSeconds: 20, memory: "256MiB" },
    async (request) => {
      try {
        requireAdmin(request);
        return await handler(request);
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        if (error instanceof TypeError || error instanceof RangeError) {
          throw new HttpsError("invalid-argument", error.message);
        }
        logger.error(fallbackMessage, error);
        throw new HttpsError("internal", fallbackMessage);
      }
    },
  );
}

function limitFrom(value, fallback = 100, maximum = 200) {
  if (value == null) return fallback;
  if (!Number.isInteger(value)) throw new TypeError("limit must be an integer");
  return Math.min(Math.max(value, 1), maximum);
}

function millis(value) {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function number(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function text(value) {
  return typeof value === "string" ? value : "";
}

function profileName(profile = {}) {
  return `${text(profile.firstName)} ${text(profile.lastName)}`.trim();
}

function ridePayload(document) {
  const data = document.data();
  const summary = data.driverSummary && typeof data.driverSummary === "object"
    ? data.driverSummary
    : {};
  return {
    rideId: document.id,
    passengerId: text(data.passengerId),
    driverId: text(data.driverId),
    driverName:
      `${text(summary.firstName)} ${text(summary.lastName)}`.trim() ||
      text(summary.name),
    status: text(data.status),
    rideOptionId: text(data.rideOptionId),
    paymentMethod: text(data.paymentMethod),
    estimatedFare: number(data.estimatedFare),
    finalFare: number(data.finalFare),
    platformFee: number(data.platformFee),
    currencyCode: text(data.currencyCode) || "SSP",
    routeDistanceMeters: number(data.routeDistanceMeters),
    requestedAtMillis: millis(data.requestedAt),
    updatedAtMillis: millis(data.updatedAt),
    completedAtMillis: millis(data.completedAt),
    cancelledAtMillis: millis(data.cancelledAt),
  };
}

exports.adminGetOperationsOverview = callable(async () => {
  const now = new Date();
  const startOfDay = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate(),
  );
  const [driverSnapshot, walletSnapshot, todayRideSnapshot, activeRideSnapshot] =
    await Promise.all([
      db.collection("drivers").limit(500).get(),
      db.collection("driver_wallets").limit(500).get(),
      db
        .collection("rides")
        .where("requestedAt", ">=", Timestamp.fromDate(startOfDay))
        .limit(500)
        .get(),
      db
        .collection("rides")
        .where("status", "in", ACTIVE_RIDE_STATUSES)
        .limit(500)
        .get(),
    ]);

  const walletByDriver = new Map(
    walletSnapshot.docs.map((document) => [document.id, document.data()]),
  );
  const driverStats = {
    total: driverSnapshot.size,
    pending: 0,
    approved: 0,
    rejected: 0,
    lowBalance: 0,
    emptyWallet: 0,
    suspended: 0,
    unclassified: 0,
  };
  for (const document of driverSnapshot.docs) {
    const profile = document.data();
    const reviewStatus = text(profile.reviewStatus) || "pending";
    if (reviewStatus in driverStats) driverStats[reviewStatus] += 1;
    const wallet = walletByDriver.get(document.id) || {};
    if (text(wallet.status) === "suspended") driverStats.suspended += 1;
    if (number(wallet.balance) <= 0) driverStats.emptyWallet += 1;
    if (wallet.isLowBalance === true || number(wallet.balance) <= number(wallet.lowBalanceThreshold || 20000)) {
      driverStats.lowBalance += 1;
    }
    const registration = profile.registration && typeof profile.registration === "object"
      ? profile.registration
      : {};
    const vehicleType = text(registration.vehicleType).toLowerCase();
    const fixedVehicle = ["boda", "boda boda", "scooter", "bajaj", "tuk-tuk", "rickshaw"].includes(vehicleType);
    if (!fixedVehicle && !text(registration.vehicleClass) && !text(profile.vehicleClass)) {
      driverStats.unclassified += 1;
    }
  }

  const rideStats = {
    today: todayRideSnapshot.size,
    active: activeRideSnapshot.size,
    completed: 0,
    cancelled: 0,
    expired: 0,
    grossFare: 0,
    platformFees: 0,
  };
  for (const document of todayRideSnapshot.docs) {
    const ride = document.data();
    const status = text(ride.status);
    if (status === "completed") rideStats.completed += 1;
    if (status === "cancelled") rideStats.cancelled += 1;
    if (status === "expired") rideStats.expired += 1;
    if (status === "completed") {
      rideStats.grossFare += number(ride.finalFare || ride.estimatedFare);
      rideStats.platformFees += number(ride.platformFee);
    }
  }

  const moneyStats = walletSnapshot.docs.reduce(
    (total, document) => {
      const wallet = document.data();
      total.walletBalances += number(wallet.balance);
      total.lifetimeCredits += number(wallet.lifetimeCredits);
      total.lifetimeDebits += number(wallet.lifetimeDebits);
      return total;
    },
    { walletBalances: 0, lifetimeCredits: 0, lifetimeDebits: 0 },
  );

  return { generatedAtMillis: Date.now(), drivers: driverStats, rides: rideStats, money: moneyStats };
}, "The Alpha operations overview could not be loaded.");

exports.adminListRides = callable(async (request) => {
  const limit = limitFrom(request.data?.limit, 100, 200);
  const snapshot = await db
    .collection("rides")
    .orderBy("updatedAt", "desc")
    .limit(limit)
    .get();
  return { rides: snapshot.docs.map(ridePayload) };
}, "The recent ride list could not be loaded.");

exports.adminListAdminActivity = callable(async (request) => {
  const limit = limitFrom(request.data?.limit, 100, 200);
  const snapshot = await db
    .collection("admin_audit_log")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();
  const driverIds = [...new Set(snapshot.docs.map((document) => text(document.get("driverId"))).filter(Boolean))];
  const profileSnapshots = driverIds.length
    ? await db.getAll(...driverIds.map((driverId) => db.collection("drivers").doc(driverId)))
    : [];
  const names = new Map(profileSnapshots.map((profile) => [profile.id, profile.exists ? profileName(profile.data()) : ""]));
  const activity = snapshot.docs.map((document) => {
    const data = document.data();
    const action = text(data.action);
    let summary = text(data.note);
    if (action === "driver_review_status") summary = `${text(data.previousStatus) || "pending"} → ${text(data.reviewStatus)}`;
    if (action === "driver_vehicle_class") summary = `${text(data.previousVehicleClass) || "unassigned"} → ${text(data.vehicleClass)}`;
    if (action === "wallet_top_up") summary = `+${number(data.amount).toLocaleString("en-US")} SSP · ${text(data.reference) || "No reference"}`;
    if (action === "wallet_status") summary = `${text(data.previousStatus) || "active"} → ${text(data.status)}`;
    return {
      activityId: document.id,
      action,
      driverId: text(data.driverId),
      driverName: names.get(text(data.driverId)) || "",
      summary,
      administratorEmail: text(data.administratorEmail),
      createdAtMillis: millis(data.createdAt),
    };
  });
  return { activity };
}, "The administrator activity log could not be loaded.");
