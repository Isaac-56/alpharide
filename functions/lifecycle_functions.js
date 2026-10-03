"use strict";

const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const {
  PLATFORM_COMMISSION_BPS,
  calculateCompletedRideAccounting,
} = require("./accounting_logic");
const { applyWalletDebit } = require("./wallet_logic");
const { validateRideId } = require("./dispatch_logic");
const {
  STALE_ACTIVE_RIDE_STATUSES,
  isStaleActiveRide,
  normalizeDriverRideStatus,
  resolveCompletedRideFare,
  resolveWaitingInterval,
  validateDriverRideTransition,
} = require("./lifecycle_logic");
const { waitingPolicyFor } = require("./ride_logic");
const { buildReceiptNumber } = require("./receipt_logic");

const REGION = "africa-south1";
const db = getFirestore();
const realtimeDb = getDatabase();

const STALE_RIDE_CANCELLATION_REASON =
  "Automatically closed after 24 hours without trip activity.";

async function syncDriverPresenceRide(driverId, rideId, completed) {
  const reference = realtimeDb.ref(`driver_locations/${driverId}`);
  if (!completed) {
    await reference.update({ activeRideId: rideId, updatedAt: Date.now() });
    return;
  }

  await reference.transaction((current) => {
    if (!current || typeof current !== "object") return;
    if (current.activeRideId !== rideId) return;
    const next = { ...current, updatedAt: Date.now() };
    delete next.activeRideId;
    return next;
  });
}

async function closeStaleActiveRide(rideReference, now) {
  let staleRide = null;

  await db.runTransaction(async (transaction) => {
    const rideSnapshot = await transaction.get(rideReference);
    if (!rideSnapshot.exists) return;

    const activityAt = [
      "updatedAt",
      "startedAt",
      "arrivedAt",
      "acceptedAt",
      "createdAt",
    ]
      .map((field) => rideSnapshot.get(field))
      .find((value) => value instanceof Timestamp);
    if (!(activityAt instanceof Timestamp)) return;
    if (!isStaleActiveRide({
      status: rideSnapshot.get("status"),
      updatedAtMillis: activityAt.toMillis(),
      nowMillis: now.toMillis(),
    })) {
      return;
    }

    const rideId = rideSnapshot.id;
    const passengerId = rideSnapshot.get("passengerId");
    const driverId = rideSnapshot.get("driverId");
    const activePassengerRef =
      typeof passengerId === "string" && passengerId
        ? db.collection("active_passenger_rides").doc(passengerId)
        : null;
    const activeDriverRef =
      typeof driverId === "string" && driverId
        ? db.collection("active_driver_rides").doc(driverId)
        : null;
    const activePassengerSnapshot = activePassengerRef
      ? await transaction.get(activePassengerRef)
      : null;
    const activeDriverSnapshot = activeDriverRef
      ? await transaction.get(activeDriverRef)
      : null;

    transaction.update(rideReference, {
      status: "cancelled",
      cancelledAt: now,
      cancelledBy: "system",
      cancellationReason: STALE_RIDE_CANCELLATION_REASON,
      cancellationReasonCode: "inactive_ride_timeout",
      isWaiting: false,
      waitingStartedAt: null,
      staleClosedAt: now,
      updatedAt: now,
    });

    if (
      activePassengerRef &&
      activePassengerSnapshot?.exists &&
      activePassengerSnapshot.get("rideId") === rideId
    ) {
      transaction.delete(activePassengerRef);
    }
    if (
      activeDriverRef &&
      activeDriverSnapshot?.exists &&
      activeDriverSnapshot.get("rideId") === rideId
    ) {
      transaction.delete(activeDriverRef);
    }

    staleRide = { rideId, driverId };
  });

  if (staleRide?.driverId) {
    await syncDriverPresenceRide(
      staleRide.driverId,
      staleRide.rideId,
      true,
    ).catch((error) => {
      logger.warn("Could not release stale driver presence", {
        ...staleRide,
        error,
      });
    });
  }

  return staleRide;
}

exports.expireStaleActiveRides = onSchedule(
  {
    region: REGION,
    schedule: "every 5 minutes",
    timeZone: "Africa/Juba",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const now = Timestamp.now();
    const candidates = await db
      .collection("rides")
      .where("status", "in", [...STALE_ACTIVE_RIDE_STATUSES])
      .limit(200)
      .get();

    const results = [];
    for (let start = 0; start < candidates.docs.length; start += 20) {
      const group = candidates.docs.slice(start, start + 20);
      results.push(...await Promise.allSettled(
        group.map((snapshot) => closeStaleActiveRide(
          snapshot.ref,
          now,
        )),
      ));
    }
    const closedRideIds = [];
    let failures = 0;

    for (const result of results) {
      if (result.status === "rejected") {
        failures += 1;
        logger.error("Unable to close a stale active ride", result.reason);
      } else if (result.value?.rideId) {
        closedRideIds.push(result.value.rideId);
      }
    }

    logger.info("Stale active ride sweep completed", {
      candidates: candidates.size,
      closed: closedRideIds.length,
      failures,
      rideIds: closedRideIds,
    });
  },
);

function requireAuthenticatedDriver(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in before updating a ride.",
    );
  }
  return uid;
}

exports.updateRideStatus = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const driverId = requireAuthenticatedDriver(request);
      const rideId = validateRideId(request.data?.rideId);
      const requestedStatus = normalizeDriverRideStatus(request.data?.status);
      const rideRef = db.collection("rides").doc(rideId);
      const activeDriverRef = db
        .collection("active_driver_rides")
        .doc(driverId);
      const rideSummaryRef = db
        .collection("driver_ride_summaries")
        .doc(driverId);
      const walletRef = db.collection("driver_wallets").doc(driverId);
      const walletTransactionRef = walletRef
        .collection("transactions")
        .doc(`ride_fee_${rideId}`);
      const receiptRef = db.collection("ride_receipts").doc(rideId);

      let resolvedStatus = requestedStatus;
      let resolvedFinalFare = null;
      let resolvedAccounting = null;
      let resolvedWaitingCharge = 0;
      let resolvedWaitingSeconds = 0;
      let resolvedWalletBalance = null;
      let resolvedReceiptNumber = null;

      await db.runTransaction(async (transaction) => {
        const rideSnapshot = await transaction.get(rideRef);
        if (!rideSnapshot.exists) {
          throw new HttpsError("not-found", "This ride no longer exists.");
        }
        if (rideSnapshot.get("driverId") !== driverId) {
          throw new HttpsError(
            "permission-denied",
            "Only the assigned driver can update this ride.",
          );
        }

        const currentStatus = rideSnapshot.get("status");
        if (currentStatus === requestedStatus) {
          resolvedStatus = currentStatus;
          resolvedFinalFare = rideSnapshot.get("finalFare") ?? null;
          resolvedWaitingCharge = rideSnapshot.get("waitingCharge") ?? 0;
          resolvedWaitingSeconds = rideSnapshot.get("waitingSeconds") ?? 0;
          if (currentStatus === "completed") {
            resolvedReceiptNumber = rideSnapshot.get("receiptNumber") ?? null;
            resolvedAccounting = {
              platformCommissionBps:
                rideSnapshot.get("platformCommissionBps") ?? null,
              platformFee: rideSnapshot.get("platformFee") ?? null,
              driverNetFare: rideSnapshot.get("driverNetFare") ?? null,
              settlementStatus: rideSnapshot.get("settlementStatus") ?? null,
            };
          }
          return;
        }

        const transition = validateDriverRideTransition(
          currentStatus,
          requestedStatus,
        );
        const passengerId = rideSnapshot.get("passengerId");
        if (typeof passengerId !== "string" || !passengerId) {
          throw new HttpsError(
            "failed-precondition",
            "This ride is missing its passenger assignment.",
          );
        }

        const activePassengerRef = db
          .collection("active_passenger_rides")
          .doc(passengerId);
        const activeDriverSnapshot = await transaction.get(activeDriverRef);
        const activePassengerSnapshot = await transaction.get(
          activePassengerRef,
        );
        const walletSnapshot = transition.completed
          ? await transaction.get(walletRef)
          : null;
        const walletTransactionSnapshot = transition.completed
          ? await transaction.get(walletTransactionRef)
          : null;

        if (
          activeDriverSnapshot.exists &&
          activeDriverSnapshot.get("rideId") !== rideId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Another active ride is assigned to this driver.",
          );
        }
        if (
          activePassengerSnapshot.exists &&
          activePassengerSnapshot.get("rideId") !== rideId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "The passenger has another active ride.",
          );
        }

        const now = Timestamp.now();
        const rideUpdate = {
          status: transition.status,
          [transition.timestampField]: now,
          updatedAt: now,
        };

        if (transition.completed) {
          const waitingStartedAt = rideSnapshot.get("waitingStartedAt");
          let billableWaitingSeconds =
            rideSnapshot.get("billableWaitingSeconds") ?? 0;
          resolvedWaitingSeconds = rideSnapshot.get("waitingSeconds") ?? 0;
          resolvedWaitingCharge = rideSnapshot.get("waitingCharge") ?? 0;

          if (
            rideSnapshot.get("isWaiting") === true &&
            waitingStartedAt instanceof Timestamp
          ) {
            const waiting = resolveWaitingInterval({
              rideOptionId: rideSnapshot.get("rideOptionId"),
              waitingSeconds: resolvedWaitingSeconds,
              billableWaitingSeconds,
              waitingStartedAtMillis: waitingStartedAt.toMillis(),
              nowMillis: now.toMillis(),
              graceSeconds: rideSnapshot.get("waitingGraceSeconds") ??
                undefined,
              waitingRatePerMinute:
                rideSnapshot.get("waitingRatePerMinute") ?? undefined,
            });
            resolvedWaitingSeconds = waiting.waitingSeconds;
            billableWaitingSeconds = waiting.billableWaitingSeconds;
            resolvedWaitingCharge = waiting.waitingCharge;
          }

          resolvedFinalFare = resolveCompletedRideFare({
            estimatedFare: rideSnapshot.get("estimatedFare"),
            finalFare: rideSnapshot.get("finalFare"),
            waitingCharge: resolvedWaitingCharge,
          });
          resolvedAccounting = calculateCompletedRideAccounting({
            grossFare: resolvedFinalFare,
            paymentMethod: rideSnapshot.get("paymentMethod"),
            commissionBps:
              rideSnapshot.get("platformCommissionBps") ??
              PLATFORM_COMMISSION_BPS,
          });
          resolvedReceiptNumber = buildReceiptNumber({
            rideId,
            completedAtMillis: now.toMillis(),
          });
          const walletBefore = walletSnapshot?.exists
            ? walletSnapshot.data()
            : {};
          const walletAfter = applyWalletDebit({
            wallet: walletBefore,
            amount: resolvedAccounting.platformFee,
          });
          resolvedWalletBalance = walletAfter.balance;
          Object.assign(rideUpdate, resolvedAccounting, {
            finalFare: resolvedFinalFare,
            receiptNumber: resolvedReceiptNumber,
            walletBalanceBefore: walletBefore.balance ?? 0,
            walletBalanceAfter: walletAfter.balance,
            isWaiting: false,
            waitingStartedAt: null,
            waitingSeconds: resolvedWaitingSeconds,
            billableWaitingSeconds,
            waitingCharge: resolvedWaitingCharge,
          });
        }

        transaction.update(rideRef, rideUpdate);

        if (transition.completed) {
          transaction.set(
            rideSummaryRef,
            {
              schemaVersion: 1,
              driverId,
              completedRideCount: FieldValue.increment(1),
              grossFareTotal: FieldValue.increment(
                resolvedAccounting.grossFare,
              ),
              platformFeeTotal: FieldValue.increment(
                resolvedAccounting.platformFee,
              ),
              driverNetFareTotal: FieldValue.increment(
                resolvedAccounting.driverNetFare,
              ),
              cashCollectedTotal: FieldValue.increment(
                resolvedAccounting.cashCollectedByDriver,
              ),
              walletFeeDebitedTotal: FieldValue.increment(
                resolvedAccounting.platformFee,
              ),
              lastCompletedRideId: rideId,
              lastCompletedAt: now,
              updatedAt: now,
            },
            { merge: true },
          );
          transaction.set(
            walletRef,
            {
              ...walletAfter,
              driverId,
              lifetimeCredits: walletSnapshot?.exists
                ? walletSnapshot.get("lifetimeCredits") ?? 0
                : 0,
              lifetimeDebits: FieldValue.increment(
                resolvedAccounting.platformFee,
              ),
              lastTransactionType: "ride_fee",
              lastTransactionAt: now,
              lastDebitAt: now,
              lastRideId: rideId,
              createdAt: walletSnapshot?.exists
                ? walletSnapshot.get("createdAt") ?? now
                : now,
              updatedAt: now,
            },
            { merge: true },
          );
          if (!walletTransactionSnapshot?.exists) {
            transaction.set(walletTransactionRef, {
              schemaVersion: 1,
              driverId,
              type: "ride_fee",
              direction: "debit",
              amount: resolvedAccounting.platformFee,
              currencyCode: walletAfter.currencyCode,
              balanceBefore: rideUpdate.walletBalanceBefore,
              balanceAfter: walletAfter.balance,
              rideId,
              note: "Alpha platform fee",
              createdAt: now,
            });
          }
          transaction.set(receiptRef, {
            schemaVersion: 1,
            receiptNumber: resolvedReceiptNumber,
            rideId,
            passengerId,
            driverId,
            rideOptionId: rideSnapshot.get("rideOptionId"),
            pickup: rideSnapshot.get("pickup"),
            destination: rideSnapshot.get("destination"),
            paymentMethod: rideSnapshot.get("paymentMethod"),
            routeDistanceMeters: rideSnapshot.get("routeDistanceMeters") ?? 0,
            estimatedFare: rideSnapshot.get("estimatedFare"),
            finalFare: resolvedFinalFare,
            waitingCharge: resolvedWaitingCharge,
            platformCommissionBps: resolvedAccounting.platformCommissionBps,
            platformFee: resolvedAccounting.platformFee,
            driverNetFare: resolvedAccounting.driverNetFare,
            currencyCode: rideSnapshot.get("currencyCode") ?? "SSP",
            completedAt: now,
            createdAt: now,
            updatedAt: now,
          }, { merge: true });
          if (
            activeDriverSnapshot.exists &&
            activeDriverSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activeDriverRef);
          }
          if (
            activePassengerSnapshot.exists &&
            activePassengerSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activePassengerRef);
          }
        } else {
          transaction.set(
            activeDriverRef,
            {
              driverId,
              rideId,
              updatedAt: now,
            },
            { merge: true },
          );
          transaction.set(
            activePassengerRef,
            {
              passengerId,
              rideId,
              updatedAt: now,
            },
            { merge: true },
          );
        }

        resolvedStatus = transition.status;
      });

      await syncDriverPresenceRide(
        driverId,
        rideId,
        resolvedStatus === "completed",
      ).catch((presenceError) => {
        logger.warn("Could not synchronize active driver presence", {
          rideId,
          driverId,
          status: resolvedStatus,
          error: presenceError,
        });
      });

      return {
        rideId,
        status: resolvedStatus,
        finalFare: resolvedFinalFare,
        platformCommissionBps:
          resolvedAccounting?.platformCommissionBps ?? null,
        platformFee: resolvedAccounting?.platformFee ?? null,
        driverNetFare: resolvedAccounting?.driverNetFare ?? null,
        settlementStatus: resolvedAccounting?.settlementStatus ?? null,
        waitingSeconds: resolvedWaitingSeconds,
        waitingCharge: resolvedWaitingCharge,
        walletBalance: resolvedWalletBalance,
        receiptNumber: resolvedReceiptNumber,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (error instanceof TypeError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      if (error instanceof RangeError) {
        throw new HttpsError("failed-precondition", error.message);
      }

      logger.error("Unable to update driver ride status", error);
      throw new HttpsError(
        "internal",
        "The ride could not be updated right now.",
      );
    }
  },
);

exports.setRideWaiting = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const driverId = requireAuthenticatedDriver(request);
      const rideId = validateRideId(request.data?.rideId);
      const isWaiting = request.data?.isWaiting;
      if (typeof isWaiting !== "boolean") {
        throw new TypeError("isWaiting must be a boolean");
      }

      const rideRef = db.collection("rides").doc(rideId);
      let response = null;

      await db.runTransaction(async (transaction) => {
        const rideSnapshot = await transaction.get(rideRef);
        if (!rideSnapshot.exists) {
          throw new HttpsError("not-found", "This ride no longer exists.");
        }
        if (rideSnapshot.get("driverId") !== driverId) {
          throw new HttpsError(
            "permission-denied",
            "Only the assigned driver can manage waiting time.",
          );
        }
        if (rideSnapshot.get("status") !== "in_progress") {
          throw new HttpsError(
            "failed-precondition",
            "Customer waiting can only be recorded during an active trip.",
          );
        }

        const currentWaiting = rideSnapshot.get("isWaiting") === true;
        const waitingStartedAt = rideSnapshot.get("waitingStartedAt");
        const rideOptionId = rideSnapshot.get("rideOptionId");
        const defaultPolicy = waitingPolicyFor(rideOptionId);
        const storedGraceSeconds = rideSnapshot.get("waitingGraceSeconds");
        const storedRatePerMinute = rideSnapshot.get("waitingRatePerMinute");
        const policy = {
          graceSeconds:
            Number.isInteger(storedGraceSeconds) && storedGraceSeconds >= 0
              ? storedGraceSeconds
              : defaultPolicy.graceSeconds,
          ratePerMinute:
            Number.isInteger(storedRatePerMinute) && storedRatePerMinute > 0
              ? storedRatePerMinute
              : defaultPolicy.ratePerMinute,
        };
        const now = Timestamp.now();
        let waitingSeconds = rideSnapshot.get("waitingSeconds") ?? 0;
        let billableWaitingSeconds =
          rideSnapshot.get("billableWaitingSeconds") ?? 0;
        let waitingCharge = rideSnapshot.get("waitingCharge") ?? 0;

        if (currentWaiting === isWaiting) {
          response = {
            rideId,
            isWaiting: currentWaiting,
            waitingStartedAtMillis:
              waitingStartedAt instanceof Timestamp
                ? waitingStartedAt.toMillis()
                : null,
            waitingSeconds,
            billableWaitingSeconds,
            waitingCharge,
            waitingGraceSeconds: policy.graceSeconds,
            waitingRatePerMinute: policy.ratePerMinute,
          };
          return;
        }

        if (isWaiting) {
          transaction.update(rideRef, {
            isWaiting: true,
            waitingStartedAt: now,
            waitingGraceSeconds: policy.graceSeconds,
            waitingRatePerMinute: policy.ratePerMinute,
            updatedAt: now,
          });
          response = {
            rideId,
            isWaiting: true,
            waitingStartedAtMillis: now.toMillis(),
            waitingSeconds,
            billableWaitingSeconds,
            waitingCharge,
            waitingGraceSeconds: policy.graceSeconds,
            waitingRatePerMinute: policy.ratePerMinute,
          };
          return;
        }

        if (!(waitingStartedAt instanceof Timestamp)) {
          throw new HttpsError(
            "failed-precondition",
            "The active waiting period is missing its server start time.",
          );
        }

        const waiting = resolveWaitingInterval({
          rideOptionId,
          waitingSeconds,
          billableWaitingSeconds,
          waitingStartedAtMillis: waitingStartedAt.toMillis(),
          nowMillis: now.toMillis(),
          graceSeconds: policy.graceSeconds,
          waitingRatePerMinute: policy.ratePerMinute,
        });
        waitingSeconds = waiting.waitingSeconds;
        billableWaitingSeconds = waiting.billableWaitingSeconds;
        waitingCharge = waiting.waitingCharge;

        transaction.update(rideRef, {
          isWaiting: false,
          waitingStartedAt: null,
          waitingSeconds,
          billableWaitingSeconds,
          waitingCharge,
          updatedAt: now,
        });
        response = {
          rideId,
          isWaiting: false,
          waitingStartedAtMillis: null,
          waitingSeconds,
          billableWaitingSeconds,
          waitingCharge,
          waitingGraceSeconds: policy.graceSeconds,
          waitingRatePerMinute: policy.ratePerMinute,
        };
      });

      return response;
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (error instanceof TypeError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      if (error instanceof RangeError) {
        throw new HttpsError("failed-precondition", error.message);
      }

      logger.error("Unable to update customer waiting time", error);
      throw new HttpsError(
        "internal",
        "Customer waiting time could not be updated right now.",
      );
    }
  },
);
