"use strict";

const LIVE_RIDE_OPTIONS = new Set(["boda", "rickshaw", "standard"]);
const LIVE_PAYMENT_METHODS = new Set(["cash"]);
const CURRENCY_CODE = "SSP";
const FARE_ROUNDING = 500;

const FARES = Object.freeze({
  boda: Object.freeze({
    minimumFare: 4000,
    baseFare: 2500,
    perMinute: 200,
    perKilometer: 1500,
  }),
  rickshaw: Object.freeze({
    minimumFare: 6000,
    baseFare: 3500,
    perMinute: 250,
    perKilometer: 2100,
  }),
  standard: Object.freeze({
    minimumFare: 10000,
    baseFare: 6000,
    perMinute: 450,
    perKilometer: 3600,
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

  const address =
    typeof raw.address === "string" ? raw.address.trim() : "";

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

function calculateFare({
  rideOptionId,
  distanceMeters,
  durationSeconds,
}) {
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

  if (
    typeof durationSeconds !== "number" ||
    !Number.isFinite(durationSeconds) ||
    durationSeconds <= 0 ||
    durationSeconds > 24 * 60 * 60
  ) {
    throw new RangeError("route duration is outside the supported range");
  }

  const distanceKilometers = distanceMeters / 1000;
  const durationMinutes = durationSeconds / 60;

  const raw =
    pricing.baseFare +
    distanceKilometers * pricing.perKilometer +
    durationMinutes * pricing.perMinute;

  const rounded = Math.ceil(raw / FARE_ROUNDING) * FARE_ROUNDING;

  return Math.max(rounded, pricing.minimumFare);
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

function isCancellableBeforePickup(status) {
  return status === "requested" || status === "offered";
}

module.exports = {
  CURRENCY_CODE,
  FARES,
  FARE_ROUNDING,
  LIVE_PAYMENT_METHODS,
  LIVE_RIDE_OPTIONS,
  calculateFare,
  isCancellableBeforePickup,
  normalizePaymentMethod,
  normalizeRideOption,
  parseGoogleDurationSeconds,
  validateCreateRideInput,
  validatePoint,
};
