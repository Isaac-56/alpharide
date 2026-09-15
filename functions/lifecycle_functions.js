"use strict";

const {
  FieldValue,
  getFirestore,
} = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const { validateRideId } = require("./dispatch_logic");
const {
  normalizeDriverRideStatus,
  validateDriverRideTransition,
} = require("./lifecycle_logic");

const REGION = "africa-south1";
const db = getFirestore();

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

      let resolvedStatus = requestedStatus;

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

        const now = FieldValue.serverTimestamp();
        transaction.update(rideRef, {
          status: transition.status,
          [transition.timestampField]: now,
          updatedAt: now,
        });

        if (transition.completed) {
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

      return {
        rideId,
        status: resolvedStatus,
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
