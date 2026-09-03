"use strict";

const { initializeApp } = require("firebase-admin/app");
const {
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const {
  HttpsError,
  onCall,
} = require("firebase-functions/v2/https");
const { logger } = require("firebase-functions");

const {
  CURRENCY_CODE,
  calculateFare,
  isCancellableBeforePickup,
  parseGoogleDurationSeconds,
  validateCreateRideInput,
} = require("./ride_logic");

initializeApp();

const db = getFirestore();
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
      "Sign in before requesting a ride.",
    );
  }

  return uid;
}

function callableError(error, fallbackMessage) {
  if (error instanceof HttpsError) {
    return error;
  }

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
      const route = await computeTrustedRoute(
        input.pickup,
        input.destination,
      );
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

      return {
        rideId: rideRef.id,
        status: "requested",
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
      const rideId =
        typeof request.data?.rideId === "string"
          ? request.data.rideId.trim()
          : "";

      if (!rideId || rideId.length > 160) {
        throw new HttpsError("invalid-argument", "A valid ride ID is required.");
      }

      const rideRef = db.collection("rides").doc(rideId);
      const activeRideRef = db
        .collection("active_passenger_rides")
        .doc(passengerId);

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

      return {
        rideId,
        status: "cancelled",
      };
    } catch (error) {
      throw callableError(error, "Unable to cancel the ride.");
    }
  },
);
