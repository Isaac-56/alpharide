"use strict";

const {
  AggregateField,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const {
  PLATFORM_COMMISSION_BPS,
  normalizeCommissionBps,
} = require("./accounting_logic");
const { FARES, farePolicyFor } = require("./ride_logic");
const { validateRideId } = require("./dispatch_logic");
const {
  normalizeAdminCancellationReason,
  projectLiveRideFare,
} = require("./admin_ride_logic");
const { requiresAdminVehicleClass } = require("./vehicle_logic");

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
const realtimeDb = getDatabase();
const FINANCE_CATEGORIES = ["standard", "boda", "rickshaw", "comfort", "premium"];

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

function ridePayload(document, nowMillis = Date.now()) {
  const data = document.data();
  const summary = data.driverSummary && typeof data.driverSummary === "object"
    ? data.driverSummary
    : {};
  const pickup = data.pickup && typeof data.pickup === "object" ? data.pickup : {};
  const destination = data.destination && typeof data.destination === "object" ? data.destination : {};
  const waitingStartedAtMillis = millis(data.waitingStartedAt);
  const projection = projectLiveRideFare({
    status: text(data.status),
    rideOptionId: text(data.rideOptionId),
    estimatedFare: data.estimatedFare,
    finalFare: data.finalFare,
    fareAtCancellation: data.fareAtCancellation,
    trackedDistanceMeters: data.trackedDistanceMeters,
    farePolicy: data.farePolicy,
    waitingCharge: data.waitingCharge,
    waitingSeconds: data.waitingSeconds,
    billableWaitingSeconds: data.billableWaitingSeconds,
    isWaiting: data.isWaiting,
    waitingStartedAtMillis,
    waitingGraceSeconds: data.waitingGraceSeconds,
    waitingRatePerMinute: data.waitingRatePerMinute,
    nowMillis,
  });
  return {
    rideId: document.id,
    passengerId: text(data.passengerId),
    driverId: text(data.driverId),
    driverName:
      `${text(summary.firstName)} ${text(summary.lastName)}`.trim() ||
      text(summary.name),
    driverPhone: text(summary.phoneNumber),
    driverPlateNumber: text(summary.plateNumber),
    passengerName: text(data.customerName),
    passengerPhone: text(data.customerPhone),
    pickupAddress: text(pickup.address),
    destinationAddress: text(destination.address),
    pickupLatitude: number(pickup.latitude),
    pickupLongitude: number(pickup.longitude),
    destinationLatitude: number(destination.latitude),
    destinationLongitude: number(destination.longitude),
    status: text(data.status),
    rideOptionId: text(data.rideOptionId),
    paymentMethod: text(data.paymentMethod),
    estimatedFare: number(data.estimatedFare),
    finalFare: number(data.finalFare),
    fareAtCancellation: number(data.fareAtCancellation),
    currentFare: projection.currentFare,
    isLiveMeteredFare: projection.isLiveMeteredFare,
    trackedDistanceMeters: projection.trackedDistanceMeters,
    waitingCharge: projection.waitingCharge,
    waitingSeconds: projection.waitingSeconds,
    billableWaitingSeconds: projection.billableWaitingSeconds,
    isWaiting: data.isWaiting === true,
    lastTrackedAtMillis: millis(data.lastTrackedAt),
    platformFee: number(data.platformFee),
    receiptNumber: text(data.receiptNumber),
    currencyCode: text(data.currencyCode) || "SSP",
    routeDistanceMeters: number(data.routeDistanceMeters),
    requestedAtMillis: millis(data.requestedAt),
    updatedAtMillis: millis(data.updatedAt),
    completedAtMillis: millis(data.completedAt),
    cancelledAtMillis: millis(data.cancelledAt),
  };
}

exports.adminGetOperationsOverview = callable(async () => {
  // South Sudan uses CAT (UTC+2) year-round. Convert Juba midnight back
  // to UTC before querying Firestore timestamps.
  const jubaOffsetMillis = 2 * 60 * 60 * 1000;
  const jubaNow = new Date(Date.now() + jubaOffsetMillis);
  const startOfDay = new Date(
    Date.UTC(
      jubaNow.getUTCFullYear(),
      jubaNow.getUTCMonth(),
      jubaNow.getUTCDate(),
    ) - jubaOffsetMillis,
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
    if (requiresAdminVehicleClass(profile) &&
      !text(registration.vehicleClass) &&
      !text(profile.vehicleClass)) {
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
  const [recentSnapshot, activeSnapshot] = await Promise.all([
    db
      .collection("rides")
      .orderBy("updatedAt", "desc")
      .limit(limit)
      .get(),
    db
      .collection("rides")
      .where("status", "in", ACTIVE_RIDE_STATUSES)
      .limit(200)
      .get(),
  ]);
  const documentsById = new Map(
    [...activeSnapshot.docs, ...recentSnapshot.docs]
      .map((document) => [document.id, document]),
  );
  const rides = [...documentsById.values()]
    .map(ridePayload)
    .sort((a, b) => number(b.updatedAtMillis) - number(a.updatedAtMillis));
  const passengerIds = [...new Set(rides.map((ride) => ride.passengerId).filter(Boolean))];
  const driverIds = [...new Set(rides.map((ride) => ride.driverId).filter(Boolean))];
  const [passengers, drivers] = await Promise.all([
    passengerIds.length
      ? db.getAll(...passengerIds.map((id) => db.collection("users").doc(id)))
      : [],
    driverIds.length
      ? db.getAll(...driverIds.map((id) => db.collection("drivers").doc(id)))
      : [],
  ]);
  const passengerMap = new Map(passengers.map((doc) => [doc.id, doc.exists ? doc.data() : {}]));
  const driverMap = new Map(drivers.map((doc) => [doc.id, doc.exists ? doc.data() : {}]));
  return {
    rides: rides.map((ride) => {
      const passenger = passengerMap.get(ride.passengerId) ?? {};
      const driver = driverMap.get(ride.driverId) ?? {};
      const registration = driver.registration && typeof driver.registration === "object"
        ? driver.registration
        : {};
      return {
        ...ride,
        passengerName: ride.passengerName || profileName(passenger),
        passengerPhone: ride.passengerPhone || text(passenger.phoneNumber),
        driverName: ride.driverName || profileName(driver),
        driverPhone: ride.driverPhone || text(driver.phoneNumber),
        driverPlateNumber: ride.driverPlateNumber || text(registration.plateNumber),
      };
    }),
  };
}, "The recent ride list could not be loaded.");

exports.adminCancelInProgressRide = callable(async (request) => {
  const rideId = validateRideId(request.data?.rideId);
  const cancellationReason = normalizeAdminCancellationReason(
    request.data?.reason,
  );
  const rideRef = db.collection("rides").doc(rideId);
  const auditRef = db.collection("admin_audit_log").doc();
  let driverId = "";
  let passengerId = "";
  let currentFare = 0;

  await db.runTransaction(async (transaction) => {
    const rideSnapshot = await transaction.get(rideRef);
    if (!rideSnapshot.exists) {
      throw new HttpsError("not-found", "This ride no longer exists.");
    }
    if (rideSnapshot.get("status") !== "in_progress") {
      throw new HttpsError(
        "failed-precondition",
        "Only a ride currently in progress can be cancelled by head office.",
      );
    }

    const data = rideSnapshot.data();
    driverId = text(data.driverId);
    passengerId = text(data.passengerId);
    const activeDriverRef = driverId
      ? db.collection("active_driver_rides").doc(driverId)
      : null;
    const activePassengerRef = passengerId
      ? db.collection("active_passenger_rides").doc(passengerId)
      : null;
    const activeDriverSnapshot = activeDriverRef
      ? await transaction.get(activeDriverRef)
      : null;
    const activePassengerSnapshot = activePassengerRef
      ? await transaction.get(activePassengerRef)
      : null;
    const now = Timestamp.now();
    const projection = projectLiveRideFare({
      status: data.status,
      rideOptionId: data.rideOptionId,
      estimatedFare: data.estimatedFare,
      finalFare: data.finalFare,
      fareAtCancellation: data.fareAtCancellation,
      trackedDistanceMeters: data.trackedDistanceMeters,
      farePolicy: data.farePolicy,
      waitingCharge: data.waitingCharge,
      waitingSeconds: data.waitingSeconds,
      billableWaitingSeconds: data.billableWaitingSeconds,
      isWaiting: data.isWaiting,
      waitingStartedAtMillis: millis(data.waitingStartedAt),
      waitingGraceSeconds: data.waitingGraceSeconds,
      waitingRatePerMinute: data.waitingRatePerMinute,
      nowMillis: now.toMillis(),
    });
    currentFare = projection.currentFare;

    transaction.update(rideRef, {
      status: "cancelled",
      offerExpiresAt: null,
      isWaiting: false,
      waitingStartedAt: null,
      waitingSeconds: projection.waitingSeconds,
      billableWaitingSeconds: projection.billableWaitingSeconds,
      waitingCharge: projection.waitingCharge,
      fareAtCancellation: currentFare,
      cancelledBy: "admin",
      cancellationReason,
      cancelledAt: now,
      updatedAt: now,
    });
    if (
      activeDriverRef &&
      activeDriverSnapshot?.exists &&
      activeDriverSnapshot.get("rideId") === rideId
    ) {
      transaction.delete(activeDriverRef);
    }
    if (
      activePassengerRef &&
      activePassengerSnapshot?.exists &&
      activePassengerSnapshot.get("rideId") === rideId
    ) {
      transaction.delete(activePassengerRef);
    }
    transaction.set(auditRef, {
      action: "active_ride_cancelled",
      rideId,
      driverId,
      passengerId,
      reason: cancellationReason,
      fareAtCancellation: currentFare,
      administratorId: request.auth.uid,
      administratorEmail: text(request.auth.token?.email),
      createdAt: now,
    });
  });

  if (driverId) {
    await realtimeDb.ref(`driver_locations/${driverId}`).transaction(
      (current) => {
        if (
          !current ||
          typeof current !== "object" ||
          current.activeRideId !== rideId
        ) {
          return;
        }
        const next = { ...current, updatedAt: Date.now() };
        delete next.activeRideId;
        return next;
      },
    ).catch((error) => {
      logger.warn("Could not release admin-cancelled driver presence", {
        rideId,
        driverId,
        error,
      });
    });
  }

  return {
    rideId,
    status: "cancelled",
    fareAtCancellation: currentFare,
    currencyCode: "SSP",
  };
}, "The in-progress ride could not be cancelled.");

exports.adminListReceipts = callable(async (request) => {
  const limit = limitFrom(request.data?.limit, 100, 200);
  const snapshot = await db
    .collection("ride_receipts")
    .orderBy("completedAt", "desc")
    .limit(limit)
    .get();
  return {
    receipts: snapshot.docs.map((document) => {
      const data = document.data();
      const pickup = data.pickup && typeof data.pickup === "object" ? data.pickup : {};
      const destination = data.destination && typeof data.destination === "object" ? data.destination : {};
      return {
        receiptId: document.id,
        receiptNumber: text(data.receiptNumber),
        rideId: text(data.rideId) || document.id,
        passengerId: text(data.passengerId),
        driverId: text(data.driverId),
        rideOptionId: text(data.rideOptionId),
        pickupAddress: text(pickup.address),
        destinationAddress: text(destination.address),
        paymentMethod: text(data.paymentMethod),
        finalFare: number(data.finalFare),
        waitingCharge: number(data.waitingCharge),
        platformFee: number(data.platformFee),
        driverNetFare: number(data.driverNetFare),
        currencyCode: text(data.currencyCode) || "SSP",
        completedAtMillis: millis(data.completedAt),
      };
    }),
  };
}, "The receipt list could not be loaded.");

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
    if (action === "driver_vehicle_class") {
      const before = Array.isArray(data.previousVehicleClasses)
        ? data.previousVehicleClasses.join(", ")
        : text(data.previousVehicleClass) || "unassigned";
      const after = Array.isArray(data.vehicleClasses)
        ? data.vehicleClasses.join(", ")
        : text(data.vehicleClass);
      summary = `${before} → ${after}`;
    }
    if (action === "wallet_top_up") summary = `+${number(data.amount).toLocaleString("en-US")} SSP · ${text(data.reference) || "No reference"}`;
    if (action === "wallet_status") summary = `${text(data.previousStatus) || "active"} → ${text(data.status)}`;
    if (action === "commission_rate") summary = `${number(data.previousCommissionBps) / 100}% → ${number(data.commissionBps) / 100}%`;
    if (action === "business_settings") summary = "Category fares, commission and exchange rates updated";
    if (action === "active_ride_cancelled") {
      summary = `${text(data.reason)} · ${number(data.fareAtCancellation).toLocaleString("en-US")} SSP at cancellation`;
    }
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

exports.adminListRecharges = callable(async (request) => {
  const limit = limitFrom(request.data?.limit, 100, 200);
  const auditSnapshot = await db
    .collection("admin_audit_log")
    .orderBy("createdAt", "desc")
    .limit(500)
    .get();
  const rechargeDocuments = auditSnapshot.docs
    .filter((document) => document.get("action") === "wallet_top_up")
    .slice(0, limit);
  const driverIds = [...new Set(
    rechargeDocuments
      .map((document) => text(document.get("driverId")))
      .filter(Boolean),
  )];
  const profiles = driverIds.length
    ? await db.getAll(
      ...driverIds.map((driverId) => db.collection("drivers").doc(driverId)),
    )
    : [];
  const profileData = new Map(
    profiles.map((profile) => [
      profile.id,
      profile.exists ? profile.data() : {},
    ]),
  );
  return {
    recharges: rechargeDocuments.map((document) => {
      const data = document.data();
      return {
        rechargeId: document.id,
        driverId: text(data.driverId),
        driverName: text(data.driverName) || profileName(profileData.get(text(data.driverId))),
        phoneNumber: text(data.phoneNumber) || text(profileData.get(text(data.driverId))?.phoneNumber),
        plateNumber: text(data.plateNumber) || text(profileData.get(text(data.driverId))?.registration?.plateNumber),
        amount: number(data.amount),
        balanceBefore: number(data.balanceBefore),
        balanceAfter: number(data.balanceAfter),
        reference: text(data.reference),
        receiptNumber: text(data.receiptNumber) || text(data.reference),
        note: text(data.note),
        administratorEmail: text(data.administratorEmail),
        createdAtMillis: millis(data.createdAt),
      };
    }),
  };
}, "The recharge history could not be loaded.");

exports.adminGetBusinessSettings = callable(async () => {
  const snapshot = await db.collection("platform_config").doc("accounting").get();
  const config = snapshot.exists ? snapshot.data() : {};
  const categories = Object.fromEntries(FINANCE_CATEGORIES.map((id) => {
    const commissionBps = normalizeCommissionBps(
      config.commissionByRideOption?.[id] ?? config.commissionBps,
    );
    return [id, {
      ...farePolicyFor(config, id),
      commissionBps,
      commissionPercent: commissionBps / 100,
    }];
  }));
  return {
    currencyCode: "SSP",
    categories,
    exchangeRates: {
      usdToSsp: number(config.exchangeRates?.usdToSsp),
      etbToSsp: number(config.exchangeRates?.etbToSsp),
    },
    updatedAtMillis: snapshot.exists ? millis(snapshot.get("updatedAt")) : null,
  };
}, "The business settings could not be loaded.");

exports.adminSetBusinessSettings = callable(async (request) => {
  const rawCategories = request.data?.categories;
  if (!rawCategories || typeof rawCategories !== "object" || Array.isArray(rawCategories)) {
    throw new TypeError("categories must be an object");
  }
  const faresByRideOption = {};
  const commissionByRideOption = {};
  for (const id of FINANCE_CATEGORIES) {
    const raw = rawCategories[id];
    if (!raw || typeof raw !== "object") throw new TypeError(`${id} settings are required`);
    const positiveInteger = (field, allowZero = false) => {
      const value = Number(raw[field]);
      if (!Number.isInteger(value) || value < (allowZero ? 0 : 1) || value > 10000000) {
        throw new RangeError(`${id}.${field} is invalid`);
      }
      return value;
    };
    const commissionBps = normalizeCommissionBps(
      Math.round(Number(raw.commissionPercent) * 100),
    );
    faresByRideOption[id] = {
      minimumFare: positiveInteger("minimumFare", true),
      baseFare: positiveInteger("baseFare", true),
      perKilometer: positiveInteger("perKilometer"),
      waitingPerMinute: positiveInteger("waitingPerMinute"),
    };
    commissionByRideOption[id] = commissionBps;
  }
  const exchange = request.data?.exchangeRates ?? {};
  const exchangeRates = {};
  for (const key of ["usdToSsp", "etbToSsp"]) {
    const value = Number(exchange[key] ?? 0);
    if (!Number.isFinite(value) || value < 0 || value > 100000000) {
      throw new RangeError(`${key} is invalid`);
    }
    exchangeRates[key] = value;
  }
  const settingsRef = db.collection("platform_config").doc("accounting");
  const auditRef = db.collection("admin_audit_log").doc();
  await db.runTransaction(async (transaction) => {
    const now = Timestamp.now();
    transaction.set(settingsRef, {
      faresByRideOption,
      commissionByRideOption,
      exchangeRates,
      updatedAt: now,
      updatedBy: request.auth.uid,
      updatedByEmail: text(request.auth.token?.email),
    }, { merge: true });
    transaction.set(auditRef, {
      action: "business_settings",
      categories: FINANCE_CATEGORIES,
      administratorId: request.auth.uid,
      administratorEmail: text(request.auth.token?.email),
      createdAt: now,
    });
  });
  return { categories: rawCategories, exchangeRates };
}, "The finance settings could not be updated.");

exports.adminGetCommissionReport = callable(async () => {
  const receipts = db.collection("ride_receipts");
  const recentSnapshot = await receipts
    .orderBy("completedAt", "desc")
    .limit(5000)
    .get();
  const nowJuba = Date.now() + 2 * 60 * 60 * 1000;
  const todayKey = new Date(nowJuba).toISOString().slice(0, 10);
  const startOfJubaDay = Timestamp.fromMillis(
    Date.parse(`${todayKey}T00:00:00.000Z`) - 2 * 60 * 60 * 1000,
  );
  const byDay = new Map();
  for (const doc of recentSnapshot.docs) {
    const data = doc.data();
    const fee = number(data.platformFee);
    const completed = millis(data.completedAt);
    if (!completed) continue;
    const day = new Date(completed + 2 * 60 * 60 * 1000).toISOString().slice(0, 10);
    byDay.set(day, (byDay.get(day) ?? 0) + fee);
  }
  let today = 0;
  let allTime = 0;
  let completedRideCount = 0;
  let byCategory = Object.fromEntries(
    FINANCE_CATEGORIES.map((id) => [id, 0]),
  );
  try {
    const [allTimeAggregate, todayAggregate, ...categoryAggregates] =
      await Promise.all([
        receipts.aggregate({
          amount: AggregateField.sum("platformFee"),
          count: AggregateField.count(),
        }).get(),
        receipts.where("completedAt", ">=", startOfJubaDay).aggregate({
          amount: AggregateField.sum("platformFee"),
        }).get(),
        ...FINANCE_CATEGORIES.map((id) =>
          receipts.where("rideOptionId", "==", id).aggregate({
            amount: AggregateField.sum("platformFee"),
          }).get(),
        ),
      ]);
    today = number(todayAggregate.data().amount);
    allTime = number(allTimeAggregate.data().amount);
    completedRideCount = number(allTimeAggregate.data().count);
    byCategory = Object.fromEntries(
      FINANCE_CATEGORIES.map((id, index) => [
        id,
        number(categoryAggregates[index].data().amount),
      ]),
    );
  } catch (error) {
    logger.warn("Commission aggregates failed; using receipt scan fallback.", {
      message: error instanceof Error ? error.message : String(error),
    });
    const fallbackSnapshot = await receipts
      .select("platformFee", "rideOptionId", "completedAt")
      .get();
    completedRideCount = fallbackSnapshot.size;
    for (const document of fallbackSnapshot.docs) {
      const data = document.data();
      const fee = number(data.platformFee);
      const category = text(data.rideOptionId).toLowerCase();
      const completedAt = millis(data.completedAt);
      allTime += fee;
      if (completedAt >= startOfJubaDay.toMillis()) today += fee;
      if (Object.hasOwn(byCategory, category)) byCategory[category] += fee;
    }
  }
  return {
    currencyCode: "SSP",
    today,
    allTime,
    completedRideCount,
    byCategory,
    daily: [...byDay.entries()].slice(0, 30).map(([date, amount]) => ({ date, amount })),
    generatedAtMillis: Date.now(),
  };
}, "The commission report could not be loaded.");
