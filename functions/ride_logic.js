"use strict";

const LIVE_RIDE_OPTIONS = new Set(["boda", "rickshaw", "standard"]);
const LIVE_PAYMENT_METHODS = new Set(["cash"]);
const CURRENCY_CODE = "SSP";
const FARE_ROUNDING = 500;
const WAITING_CHARGE_ROUNDING = 100;
const WAITING_GRACE_SECONDS = 2 * 60;

const FARES = Object.freeze({
  boda: Object.freeze({
    minimumFare: 4000,
    baseFare: 2500,
    perKilometer: 1500,
    waitingPerMinute: 200,
  }),
  rickshaw: Object.freeze({
    minimumFare: 6000,
    baseFare: 3500,
    perKilometer: 2100,
    waitingPerMinute: 250,
  }),
  standard: Object.freeze({
    minimumFare: 10000,
    baseFare: 6000,
    perKilometer: 3600,
    waitingPerMinute: 450,
  }),
});

function normalizeRideOption(value) {
  if (typeof value !== "string") {
    throw new TypeError("rideOptionId must be a string");
  }

  const normalized = value.trim().toLowerCase();
  if (!LIVE_RIDE_OPTIONS.has(normalized)) {
    throw new RangeError("ride option is not enabled for live dispatch");
  }

  return normalized;
}

function normalizePaymentMethod(value) {
  if (typeof value !== "string") {
    throw new TypeError("paymentMethod must be a string");
  }

  const normalized = value.trim().toLowerCase();
  if (!LIVE_PAYMENT_METHODS.has(normalized)) {
    throw new RangeError("payment method is not enabled for live rides");
  }

  return normalized;
}

function validateCoordinate(value, minimum, maximum, fieldName) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${fieldName} must be a finite number`);
  }

  if (value < minimum || value > maximum) {
    throw new RangeError(`${fieldName} is outside its valid range`);
  }

  return value;
}

function validatePoint(raw, fieldName) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError(`${fieldName} must be an object`);
  }

  const address = typeof raw.address === "string" ? raw.address.trim() : "";
  if (!address || address.length > 240) {
    throw new RangeError(
      `${fieldName}.address must contain between 1 and 240 characters`,
    );
  }

  return Object.freeze({
    address,
    latitude: validateCoordinate(
      raw.latitude,
      -90,
      90,
      `${fieldName}.latitude`,
    ),
    longitude: validateCoordinate(
      raw.longitude,
      -180,
      180,
      `${fieldName}.longitude`,
    ),
  });
}

function validateCreateRideInput(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError("ride input must be an object");
  }

  const pickup = validatePoint(raw.pickup, "pickup");
  const destination = validatePoint(raw.destination, "destination");

  if (
    Math.abs(pickup.latitude - destination.latitude) < 0.00001 &&
    Math.abs(pickup.longitude - destination.longitude) < 0.00001
  ) {
    throw new RangeError("pickup and destination cannot be the same");
  }

  return Object.freeze({
    pickup,
    destination,
    rideOptionId: normalizeRideOption(raw.rideOptionId),
    paymentMethod: normalizePaymentMethod(raw.paymentMethod),
  });
}

function calculateFare({ rideOptionId, distanceMeters }) {
  const normalizedRide = normalizeRideOption(rideOptionId);
  const pricing = FARES[normalizedRide];

  if (
    typeof distanceMeters !== "number" ||
    !Number.isFinite(distanceMeters) ||
    distanceMeters <= 0 ||
    distanceMeters > 500000
  ) {
    throw new RangeError("route distance is outside the supported range");
  }

  const distanceKilometers = distanceMeters / 1000;
  const raw =
    pricing.baseFare +
    distanceKilometers * pricing.perKilometer;
  const rounded = Math.ceil(raw / FARE_ROUNDING) * FARE_ROUNDING;

  return Math.max(rounded, pricing.minimumFare);
}

function calculateWaitingCharge({
  rideOptionId,
  billableWaitingSeconds,
  ratePerMinute,
}) {
  const normalizedRide = normalizeRideOption(rideOptionId);
  const pricing = FARES[normalizedRide];
  const effectiveRate = ratePerMinute ?? pricing.waitingPerMinute;

  if (
    !Number.isInteger(billableWaitingSeconds) ||
    billableWaitingSeconds < 0 ||
    billableWaitingSeconds > 24 * 60 * 60
  ) {
    throw new RangeError("billable waiting time is outside the supported range");
  }
  if (!Number.isInteger(effectiveRate) || effectiveRate <= 0) {
    throw new RangeError("waiting rate must be a positive integer");
  }

  if (billableWaitingSeconds === 0) return 0;

  const raw = (billableWaitingSeconds / 60) * effectiveRate;
  return Math.ceil(raw / WAITING_CHARGE_ROUNDING) *
    WAITING_CHARGE_ROUNDING;
}

function waitingPolicyFor(rideOptionId) {
  const normalizedRide = normalizeRideOption(rideOptionId);
  return Object.freeze({
    graceSeconds: WAITING_GRACE_SECONDS,
    ratePerMinute: FARES[normalizedRide].waitingPerMinute,
  });
}

function parseGoogleDurationSeconds(value) {
  if (typeof value !== "string" || !value.endsWith("s")) {
    throw new TypeError("Google route duration is invalid");
  }

  const seconds = Number(value.slice(0, -1));
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new RangeError("Google route duration is invalid");
  }

  return seconds;
}

function validateCancellationReason(value) {
  if (typeof value !== "string") {
    throw new TypeError("cancellation reason must be a string");
  }

  const normalized = value.trim();
  if (!normalized || normalized.length > 120) {
    throw new RangeError(
      "cancellation reason must contain between 1 and 120 characters",
    );
  }

  return normalized;
}

function isCancellableBeforePickup(status) {
  return new Set([
    "requested",
    "offered",
    "accepted",
    "driver_arriving",
    "arrived",
  ]).has(status);
}

module.exports = {
  CURRENCY_CODE,
  FARES,
  FARE_ROUNDING,
  WAITING_CHARGE_ROUNDING,
  WAITING_GRACE_SECONDS,
  LIVE_PAYMENT_METHODS,
  LIVE_RIDE_OPTIONS,
  calculateFare,
  calculateWaitingCharge,
  isCancellableBeforePickup,
  normalizePaymentMethod,
  normalizeRideOption,
  parseGoogleDurationSeconds,
  validateCoordinate,
  validateCancellationReason,
  validateCreateRideInput,
  validatePoint,
  waitingPolicyFor,
};
