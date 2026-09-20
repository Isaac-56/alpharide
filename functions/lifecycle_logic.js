"use strict";

const {
  WAITING_GRACE_SECONDS,
  calculateWaitingCharge,
} = require("./ride_logic");

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
  STATUS_TIMESTAMP_FIELDS,
  normalizeDriverRideStatus,
  resolveCompletedRideFare,
  resolveWaitingInterval,
  validateDriverRideTransition,
};