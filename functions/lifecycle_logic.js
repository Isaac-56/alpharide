"use strict";

const {
  WAITING_GRACE_SECONDS,
  calculateFare,
  calculateWaitingCharge,
} = require("./ride_logic");
const { haversineDistanceMeters } = require("./dispatch_logic");

const MAX_TRACKING_ACCURACY_METERS = 100;
const MAX_TRACKED_DISTANCE_METERS = 500000;
const MIN_TRACKED_MOVEMENT_METERS = 3;

function normalizeRideProgressPoint(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError("ride progress point must be an object");
  }
  const latitude = Number(raw.latitude);
  const longitude = Number(raw.longitude);
  const accuracy = Number(raw.accuracy);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    throw new RangeError("ride progress latitude is invalid");
  }
  if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new RangeError("ride progress longitude is invalid");
  }
  if (
    !Number.isFinite(accuracy) ||
    accuracy < 0 ||
    accuracy > MAX_TRACKING_ACCURACY_METERS
  ) {
    throw new RangeError("ride progress accuracy is insufficient");
  }
  return Object.freeze({ latitude, longitude, accuracy });
}

function resolveTrackedRideProgress({
  previousPoint,
  previousAtMillis,
  nextPoint,
  nowMillis,
  trackedDistanceMeters = 0,
}) {
  const next = normalizeRideProgressPoint(nextPoint);
  if (!Number.isFinite(nowMillis)) {
    throw new RangeError("ride progress time is invalid");
  }
  const currentDistance = Number(trackedDistanceMeters);
  if (
    !Number.isFinite(currentDistance) ||
    currentDistance < 0 ||
    currentDistance > MAX_TRACKED_DISTANCE_METERS
  ) {
    throw new RangeError("tracked ride distance is invalid");
  }
  if (!previousPoint || !Number.isFinite(previousAtMillis)) {
    return Object.freeze({
      point: next,
      trackedDistanceMeters: Math.round(currentDistance),
      segmentDistanceMeters: 0,
    });
  }

  const previous = normalizeRideProgressPoint(previousPoint);
  const elapsedSeconds = Math.max(0, (nowMillis - previousAtMillis) / 1000);
  const segment = haversineDistanceMeters(previous, next);
  // Ignore GPS drift and physically implausible jumps. The generous speed cap
  // still covers emergency driving while preventing a forged fare increase.
  const maximumPlausibleSegment = Math.max(250, elapsedSeconds * 60 + 100);
  const acceptedSegment =
    segment >= MIN_TRACKED_MOVEMENT_METERS &&
    segment <= maximumPlausibleSegment
      ? segment
      : 0;
  return Object.freeze({
    point: next,
    trackedDistanceMeters: Math.min(
      MAX_TRACKED_DISTANCE_METERS,
      Math.round(currentDistance + acceptedSegment),
    ),
    segmentDistanceMeters: Math.round(acceptedSegment),
  });
}

const DRIVER_RIDE_TRANSITIONS = Object.freeze({
  accepted: "driver_arriving",
  driver_arriving: "arrived",
  arrived: "in_progress",
  in_progress: "completed",
});

const STATUS_TIMESTAMP_FIELDS = Object.freeze({
  driver_arriving: "driverArrivingAt",
  arrived: "arrivedAt",
  in_progress: "startedAt",
  completed: "completedAt",
});

const STALE_ACTIVE_RIDE_TIMEOUT_MS = 24 * 60 * 60 * 1000;
const STALE_ACTIVE_RIDE_STATUSES = Object.freeze(new Set([
  "accepted",
  "driver_arriving",
  "arrived",
  "in_progress",
]));

function isStaleActiveRide({ status, updatedAtMillis, nowMillis }) {
  if (typeof status !== "string") return false;
  const normalizedStatus = status.trim().toLowerCase();
  if (!STALE_ACTIVE_RIDE_STATUSES.has(normalizedStatus)) return false;
  if (!Number.isFinite(updatedAtMillis) || !Number.isFinite(nowMillis)) {
    return false;
  }
  if (nowMillis < updatedAtMillis) return false;

  return nowMillis - updatedAtMillis >= STALE_ACTIVE_RIDE_TIMEOUT_MS;
}

function resolveDriverRideLock({
  status,
  assignedDriverId,
  driverId,
  updatedAtMillis,
  nowMillis,
}) {
  if (typeof driverId !== "string" || !driverId.trim()) return "release";
  if (assignedDriverId !== driverId) return "release";
  if (typeof status !== "string") return "release";

  const normalizedStatus = status.trim().toLowerCase();
  if (!STALE_ACTIVE_RIDE_STATUSES.has(normalizedStatus)) return "release";
  if (!Number.isFinite(updatedAtMillis)) return "active";

  return isStaleActiveRide({
    status: normalizedStatus,
    updatedAtMillis,
    nowMillis,
  }) ? "stale" : "active";
}

function normalizeDriverRideStatus(value) {
  if (typeof value !== "string") {
    throw new TypeError("ride status must be a string");
  }

  const normalized = value.trim().toLowerCase();
  if (!Object.prototype.hasOwnProperty.call(STATUS_TIMESTAMP_FIELDS, normalized)) {
    throw new RangeError("ride status is not a driver lifecycle transition");
  }

  return normalized;
}

function validateDriverRideTransition(currentStatus, requestedStatus) {
  if (typeof currentStatus !== "string" || !currentStatus.trim()) {
    throw new TypeError("current ride status is invalid");
  }

  const current = currentStatus.trim().toLowerCase();
  const next = normalizeDriverRideStatus(requestedStatus);
  const expected = DRIVER_RIDE_TRANSITIONS[current];

  if (expected !== next) {
    throw new RangeError(`ride cannot transition from ${current} to ${next}`);
  }

  return Object.freeze({
    status: next,
    timestampField: STATUS_TIMESTAMP_FIELDS[next],
    completed: next === "completed",
  });
}

function resolveCompletedRideFare({
  estimatedFare,
  finalFare,
  waitingCharge = 0,
  rideOptionId,
  actualDistanceMeters,
  farePolicy,
}) {
  if (Number.isInteger(finalFare) && finalFare > 0) {
    return finalFare;
  }

  if (!Number.isInteger(estimatedFare) || estimatedFare <= 0) {
    throw new RangeError("completed ride is missing a valid trusted fare");
  }

  if (!Number.isInteger(waitingCharge) || waitingCharge < 0) {
    throw new RangeError("completed ride has an invalid waiting charge");
  }

  if (Number.isInteger(actualDistanceMeters) && actualDistanceMeters >= 0) {
    return calculateFare({
      rideOptionId,
      distanceMeters: actualDistanceMeters,
      allowZeroDistance: true,
      farePolicy,
    }) + waitingCharge;
  }

  return estimatedFare + waitingCharge;
}

function resolveWaitingInterval({
  rideOptionId,
  waitingSeconds = 0,
  billableWaitingSeconds = 0,
  waitingStartedAtMillis,
  nowMillis,
  graceSeconds = WAITING_GRACE_SECONDS,
  waitingRatePerMinute,
}) {
  if (!Number.isInteger(waitingSeconds) || waitingSeconds < 0) {
    throw new RangeError("waitingSeconds must be a non-negative integer");
  }
  if (
    !Number.isInteger(billableWaitingSeconds) ||
    billableWaitingSeconds < 0 ||
    billableWaitingSeconds > waitingSeconds
  ) {
    throw new RangeError(
      "billableWaitingSeconds must be a valid accumulated duration",
    );
  }
  if (!Number.isInteger(graceSeconds) || graceSeconds < 0) {
    throw new RangeError("waiting grace period is invalid");
  }
  if (
    !Number.isFinite(waitingStartedAtMillis) ||
    !Number.isFinite(nowMillis) ||
    nowMillis < waitingStartedAtMillis
  ) {
    throw new RangeError("waiting interval timestamps are invalid");
  }

  const intervalSeconds = Math.min(
    Math.floor((nowMillis - waitingStartedAtMillis) / 1000),
    4 * 60 * 60,
  );
  const intervalBillableSeconds = Math.max(
    0,
    intervalSeconds - graceSeconds,
  );
  const totalWaitingSeconds = waitingSeconds + intervalSeconds;
  const totalBillableWaitingSeconds =
    billableWaitingSeconds + intervalBillableSeconds;

  return Object.freeze({
    intervalSeconds,
    intervalBillableSeconds,
    waitingSeconds: totalWaitingSeconds,
    billableWaitingSeconds: totalBillableWaitingSeconds,
    waitingCharge: calculateWaitingCharge({
      rideOptionId,
      billableWaitingSeconds: totalBillableWaitingSeconds,
      ratePerMinute: waitingRatePerMinute,
    }),
  });
}

module.exports = {
  DRIVER_RIDE_TRANSITIONS,
  STALE_ACTIVE_RIDE_STATUSES,
  STALE_ACTIVE_RIDE_TIMEOUT_MS,
  STATUS_TIMESTAMP_FIELDS,
  isStaleActiveRide,
  normalizeDriverRideStatus,
  normalizeRideProgressPoint,
  resolveDriverRideLock,
  resolveCompletedRideFare,
  resolveTrackedRideProgress,
  resolveWaitingInterval,
  validateDriverRideTransition,
};
