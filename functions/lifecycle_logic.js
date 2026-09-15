"use strict";

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

module.exports = {
  DRIVER_RIDE_TRANSITIONS,
  STATUS_TIMESTAMP_FIELDS,
  normalizeDriverRideStatus,
  validateDriverRideTransition,
};
