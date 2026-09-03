"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const {
  OFFER_WINDOW_MS,
  profileAllowsDispatch,
  selectPresenceCandidates,
  validateRideId,
} = require("./dispatch_logic");
const {
  CURRENCY_CODE,
  calculateFare,
  isCancellableBeforePickup,
  parseGoogleDurationSeconds,
  validateCancellationReason,
  validateCreateRideInput,
} = require("./ride_logic");

initializeApp();

const db = getFirestore();
const realtimeDb = getDatabase();
const googleRoutesApiKey = defineSecret("GOOGLE_ROUTES_API_KEY");

const REGION = "africa-south1";
const ACTIVE_RIDE_STATUSES = new Set([
  "requested",
  "offered",
  "accepted",
  "driver_arriving",
  "arrived",
  "in_progress",
]);

function requireAuthenticatedUser(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in before using the live ride service.",
    );
  }
  return uid;
}

function callableError(error, fallbackMessage) {
  if (error instanceof HttpsError) return error;

  if (error instanceof TypeError || error instanceof RangeError) {
    return new HttpsError("invalid-argument", error.message);
  }

  logger.error(fallbackMessage, error);
  return new HttpsError("internal", fallbackMessage);
}

async function computeTrustedRoute(pickup, destination) {
  const response = await fetch(
    "https://routes.googleapis.com/directions/v2:computeRoutes",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": googleRoutesApiKey.value(),
        "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
      },
      body: JSON.stringify({
        origin: {
          location: {
            latLng: {
              latitude: pickup.latitude,
              longitude: pickup.longitude,
            },
          },
        },
        destination: {
          location: {
            latLng: {
              latitude: destination.latitude,
              longitude: destination.longitude,
            },
          },
        },
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_AWARE",
        computeAlternativeRoutes: false,
        languageCode: "en-US",
        units: "METRIC",
      }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    logger.error("Google Routes rejected a ride quote", {
      status: response.status,
      body: body.slice(0, 1000),
    });
    throw new HttpsError(
      "unavailable",
      "A road route could not be calculated right now.",
    );
  }

  const payload = await response.json();
  const route = payload?.routes?.[0];
  if (
    !route ||
    typeof route.distanceMeters !== "number" ||
    typeof route.duration !== "string"
  ) {
    throw new HttpsError(
      "unavailable",
      "No drivable route was returned for this trip.",
    );
  }

  return {
    distanceMeters: route.distanceMeters,
    durationSeconds: parseGoogleDurationSeconds(route.duration),
  };
}

function offerReference(driverId, rideId) {
  return db
    .collection("driver_ride_offers")
    .doc(driverId)
    .collection("offers")
    .doc(rideId);
}

async function markOffers(rideId, driverIds, status) {
  if (!Array.isArray(driverIds) || driverIds.length === 0) return;

  const batch = db.batch();
  const now = FieldValue.serverTimestamp();
  for (const driverId of driverIds) {
    if (typeof driverId !== "string" || !driverId) continue;
    batch.set(
      offerReference(driverId, rideId),
      { status, respondedAt: now },
      { merge: true },
    );
  }
  await batch.commit();
}

async function dispatchRide({
  rideId,
  passengerId,
  pickup,
  destination,
  rideOptionId,
  requiredVehicleType,
  paymentMethod,
  estimatedFare,
}) {
  const rideRef = db.collection("rides").doc(rideId);
  const presenceSnapshot = await realtimeDb.ref("driver_locations").get();
  const presenceMap = presenceSnapshot.exists()
    ? presenceSnapshot.val()
    : null;
  const presenceCandidates = selectPresenceCandidates({
    presenceMap,
    pickup,
    requiredVehicleType,
  });

  if (presenceCandidates.length === 0) {
    await rideRef.update({
      dispatchState: "no_candidates",
      dispatchCandidateCount: 0,
      dispatchAttemptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "requested";
  }

  const verifiedCandidates = [];
  for (const candidate of presenceCandidates) {
    const profileSnapshot = await db
      .collection("drivers")
      .doc(candidate.driverId)
      .get();
    if (
      profileSnapshot.exists &&
      profileAllowsDispatch(profileSnapshot.data(), requiredVehicleType)
    ) {
      verifiedCandidates.push(candidate);
    }
  }

  if (verifiedCandidates.length === 0) {
    await rideRef.update({
      dispatchState: "no_approved_candidates",
      dispatchCandidateCount: 0,
      dispatchAttemptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "requested";
  }

  const driverIds = verifiedCandidates.map((candidate) => candidate.driverId);
  const expiresAt = Timestamp.fromMillis(Date.now() + OFFER_WINDOW_MS);
  const batch = db.batch();

  for (const candidate of verifiedCandidates) {
    batch.set(offerReference(candidate.driverId, rideId), {
      schemaVersion: 1,
      rideId,
      driverId: candidate.driverId,
      passengerId,
      status: "pending",
      pickup,
      destination,
      rideOptionId,
      requiredVehicleType,
      paymentMethod,
      estimatedFare,
      currencyCode: CURRENCY_CODE,
      distanceToPickupMeters: candidate.distanceToPickupMeters,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      respondedAt: null,
    });
  }

  batch.update(rideRef, {
    status: "offered",
    offeredDriverIds: driverIds,
    offerExpiresAt: expiresAt,
    dispatchState: "offers_created",
    dispatchCandidateCount: driverIds.length,
    dispatchAttemptedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return "offered";
}

exports.createRide = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const passengerId = requireAuthenticatedUser(request);
      const input = validateCreateRideInput(request.data);
      const route = await computeTrustedRoute(input.pickup, input.destination);
      const estimatedFare = calculateFare({
        rideOptionId: input.rideOptionId,
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
      });

      const rideRef = db.collection("rides").doc();
      const activeRideRef = db
        .collection("active_passenger_rides")
        .doc(passengerId);

      await db.runTransaction(async (transaction) => {
        const activeSnapshot = await transaction.get(activeRideRef);

        if (activeSnapshot.exists) {
          const activeRideId = activeSnapshot.get("rideId");
          if (typeof activeRideId === "string" && activeRideId) {
            const existingRideRef = db.collection("rides").doc(activeRideId);
            const existingRide = await transaction.get(existingRideRef);
            if (
              existingRide.exists &&
              ACTIVE_RIDE_STATUSES.has(existingRide.get("status"))
            ) {
              throw new HttpsError(
                "already-exists",
                "You already have an active ride.",
                { rideId: activeRideId },
              );
            }
          }
          transaction.delete(activeRideRef);
        }

        const now = FieldValue.serverTimestamp();
        transaction.create(rideRef, {
          schemaVersion: 1,
          passengerId,
          driverId: null,
          status: "requested",
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: input.paymentMethod,
          estimatedFare,
          finalFare: null,
          currencyCode: CURRENCY_CODE,
          routeDistanceMeters: Math.round(route.distanceMeters),
          routeDurationSeconds: Math.round(route.durationSeconds),
          cancelledBy: null,
          cancellationReason: null,
          offeredDriverIds: [],
          dispatchState: "pending",
          requestedAt: now,
          updatedAt: now,
          acceptedAt: null,
          arrivedAt: null,
          startedAt: null,
          completedAt: null,
          cancelledAt: null,
        });

        transaction.set(activeRideRef, {
          passengerId,
          rideId: rideRef.id,
          createdAt: now,
          updatedAt: now,
        });
      });

      let status = "requested";
      try {
        status = await dispatchRide({
          rideId: rideRef.id,
          passengerId,
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: input.paymentMethod,
          estimatedFare,
        });
      } catch (dispatchError) {
        logger.error("Initial ride dispatch failed", {
          rideId: rideRef.id,
          error: dispatchError,
        });
        await rideRef
          .update({
            dispatchState: "error",
            dispatchAttemptedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          })
          .catch(() => {});
      }

      return {
        rideId: rideRef.id,
        status,
        estimatedFare,
        currencyCode: CURRENCY_CODE,
        routeDistanceMeters: Math.round(route.distanceMeters),
        routeDurationSeconds: Math.round(route.durationSeconds),
      };
    } catch (error) {
      throw callableError(error, "Unable to create the ride.");
    }
  },
);

exports.cancelRide = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const passengerId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const cancellationReason = validateCancellationReason(
        request.data?.reason,
      );
      const rideRef = db.collection("rides").doc(rideId);
      const activeRideRef = db
        .collection("active_passenger_rides")
        .doc(passengerId);
      let offeredDriverIds = [];

      await db.runTransaction(async (transaction) => {
        const rideSnapshot = await transaction.get(rideRef);
        const activeSnapshot = await transaction.get(activeRideRef);

        if (!rideSnapshot.exists) {
          throw new HttpsError("not-found", "The ride no longer exists.");
        }
        if (rideSnapshot.get("passengerId") !== passengerId) {
          throw new HttpsError(
            "permission-denied",
            "This ride belongs to another passenger.",
          );
        }

        offeredDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const status = rideSnapshot.get("status");

        if (status === "cancelled") {
          if (
            activeSnapshot.exists &&
            activeSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activeRideRef);
          }
          return;
        }

        if (!isCancellableBeforePickup(status)) {
          throw new HttpsError(
            "failed-precondition",
            "This ride can no longer be cancelled from the passenger app.",
          );
        }

        transaction.update(rideRef, {
          status: "cancelled",
          cancelledBy: "passenger",
          cancellationReason,
          cancelledAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        if (
          activeSnapshot.exists &&
          activeSnapshot.get("rideId") === rideId
        ) {
          transaction.delete(activeRideRef);
        }
      });

      try {
        await markOffers(rideId, offeredDriverIds, "cancelled");
      } catch (cleanupError) {
        logger.warn("Could not close cancelled ride offers", {
          rideId,
          error: cleanupError,
        });
      }

      return { rideId, status: "cancelled" };
    } catch (error) {
      throw callableError(error, "Unable to cancel the ride.");
    }
  },
);

exports.acceptRideOffer = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const driverId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const rideRef = db.collection("rides").doc(rideId);
      const offerRef = offerReference(driverId, rideId);
      const profileRef = db.collection("drivers").doc(driverId);
      const activeDriverRef = db
        .collection("active_driver_rides")
        .doc(driverId);
      let competingDriverIds = [];

      await db.runTransaction(async (transaction) => {
        const offerSnapshot = await transaction.get(offerRef);
        const rideSnapshot = await transaction.get(rideRef);
        const profileSnapshot = await transaction.get(profileRef);
        const activeDriverSnapshot = await transaction.get(activeDriverRef);

        if (!offerSnapshot.exists || !rideSnapshot.exists) {
          throw new HttpsError("not-found", "This ride offer is no longer available.");
        }

        if (
          rideSnapshot.get("status") === "accepted" &&
          rideSnapshot.get("driverId") === driverId
        ) {
          return;
        }

        if (offerSnapshot.get("status") !== "pending") {
          throw new HttpsError("failed-precondition", "This offer is no longer active.");
        }

        const expiresAt = offerSnapshot.get("expiresAt");
        if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() <= Date.now()) {
          throw new HttpsError("failed-precondition", "This ride offer has expired.");
        }

        if (
          rideSnapshot.get("status") !== "offered" ||
          rideSnapshot.get("driverId") != null
        ) {
          throw new HttpsError("already-exists", "Another driver already accepted this ride.");
        }

        const requiredVehicleType = rideSnapshot.get("requiredVehicleType");
        if (
          !profileSnapshot.exists ||
          !profileAllowsDispatch(profileSnapshot.data(), requiredVehicleType)
        ) {
          throw new HttpsError(
            "permission-denied",
            "Your approved vehicle is not eligible for this ride.",
          );
        }

        if (
          activeDriverSnapshot.exists &&
          activeDriverSnapshot.get("rideId") !== rideId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Finish your active ride before accepting another request.",
          );
        }

        competingDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const now = FieldValue.serverTimestamp();

        transaction.update(rideRef, {
          status: "accepted",
          driverId,
          acceptedAt: now,
          updatedAt: now,
        });
        transaction.update(offerRef, {
          status: "accepted",
          respondedAt: now,
        });
        transaction.set(activeDriverRef, {
          driverId,
          rideId,
          createdAt: now,
          updatedAt: now,
        });
      });

      const competingOffers = competingDriverIds.filter(
        (candidateId) => candidateId !== driverId,
      );
      try {
        await markOffers(rideId, competingOffers, "expired");
      } catch (cleanupError) {
        logger.warn("Could not expire competing ride offers", {
          rideId,
          driverId,
          error: cleanupError,
        });
      }

      return { rideId, status: "accepted", driverId };
    } catch (error) {
      throw callableError(error, "Unable to accept the ride offer.");
    }
  },
);

exports.rejectRideOffer = onCall(
  {
    region: REGION,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const driverId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const rideRef = db.collection("rides").doc(rideId);
      const offerRef = offerReference(driverId, rideId);

      await db.runTransaction(async (transaction) => {
        const offerSnapshot = await transaction.get(offerRef);
        const rideSnapshot = await transaction.get(rideRef);

        if (!offerSnapshot.exists) {
          throw new HttpsError("not-found", "This ride offer is no longer available.");
        }

        const currentOfferStatus = offerSnapshot.get("status");
        if (currentOfferStatus === "rejected" || currentOfferStatus === "expired") {
          return;
        }
        if (currentOfferStatus !== "pending") {
          throw new HttpsError("failed-precondition", "This offer is no longer active.");
        }

        const status =
          rideSnapshot.exists && rideSnapshot.get("status") === "offered"
            ? "rejected"
            : "expired";
        transaction.update(offerRef, {
          status,
          respondedAt: FieldValue.serverTimestamp(),
        });
      });

      return { rideId, status: "rejected", driverId };
    } catch (error) {
      throw callableError(error, "Unable to reject the ride offer.");
    }
  },
);
