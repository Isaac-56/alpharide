"use strict";

const { calculateFare, farePolicyFor } = require("./ride_logic");
const { resolveWaitingInterval } = require("./lifecycle_logic");

function nonNegativeInteger(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.round(parsed) : 0;
}

function normalizeAdminCancellationReason(value) {
  if (typeof value !== "string") {
    throw new TypeError("A cancellation reason is required");
  }
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.length < 5 || normalized.length > 240) {
    throw new RangeError("The cancellation reason must be 5 to 240 characters");
  }
  return normalized;
}

function projectLiveRideFare({
  status,
  rideOptionId,
  estimatedFare,
  finalFare,
  fareAtCancellation,
  trackedDistanceMeters,
  farePolicy,
  waitingCharge,
  waitingSeconds,
  billableWaitingSeconds,
  isWaiting,
  waitingStartedAtMillis,
  waitingGraceSeconds,
  waitingRatePerMinute,
  nowMillis,
}) {
  const estimate = nonNegativeInteger(estimatedFare);
  const final = nonNegativeInteger(finalFare);
  const cancellationFare = nonNegativeInteger(fareAtCancellation);
  const distance = nonNegativeInteger(trackedDistanceMeters);
  let projectedWaitingCharge = nonNegativeInteger(waitingCharge);
  let projectedWaitingSeconds = nonNegativeInteger(waitingSeconds);
  let projectedBillableWaitingSeconds = nonNegativeInteger(
    billableWaitingSeconds,
  );

  if (status !== "in_progress") {
    return Object.freeze({
      currentFare: final || cancellationFare || estimate,
      trackedDistanceMeters: distance,
      waitingCharge: projectedWaitingCharge,
      waitingSeconds: projectedWaitingSeconds,
      billableWaitingSeconds: projectedBillableWaitingSeconds,
      isLiveMeteredFare: false,
    });
  }

  if (
    isWaiting === true &&
    Number.isFinite(waitingStartedAtMillis) &&
    Number.isFinite(nowMillis) &&
    nowMillis >= waitingStartedAtMillis
  ) {
    const waiting = resolveWaitingInterval({
      rideOptionId,
      waitingSeconds: projectedWaitingSeconds,
      billableWaitingSeconds: projectedBillableWaitingSeconds,
      waitingStartedAtMillis,
      nowMillis,
      graceSeconds: Number.isInteger(waitingGraceSeconds)
        ? waitingGraceSeconds
        : 0,
      waitingRatePerMinute: Number.isFinite(Number(waitingRatePerMinute))
        ? Number(waitingRatePerMinute)
        : undefined,
    });
    projectedWaitingCharge = waiting.waitingCharge;
    projectedWaitingSeconds = waiting.waitingSeconds;
    projectedBillableWaitingSeconds = waiting.billableWaitingSeconds;
  }

  let distanceFare = estimate;
  try {
    distanceFare = calculateFare({
      rideOptionId,
      distanceMeters: distance,
      farePolicy: farePolicyFor({
        faresByRideOption: farePolicy ? { [rideOptionId]: farePolicy } : {},
      }, rideOptionId),
    });
  } catch (_) {
    distanceFare = estimate;
  }

  return Object.freeze({
    currentFare: distanceFare + projectedWaitingCharge,
    trackedDistanceMeters: distance,
    waitingCharge: projectedWaitingCharge,
    waitingSeconds: projectedWaitingSeconds,
    billableWaitingSeconds: projectedBillableWaitingSeconds,
    isLiveMeteredFare: true,
  });
}

module.exports = {
  normalizeAdminCancellationReason,
  projectLiveRideFare,
};
