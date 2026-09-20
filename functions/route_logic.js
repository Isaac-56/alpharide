"use strict";

const {
  parseGoogleDurationSeconds,
  validateCoordinate,
} = require("./ride_logic");

const ROUTE_PREVIEW_REQUEST_LIMIT = 30;
const ROUTE_PREVIEW_WINDOW_MS = 60 * 1000;
const MAX_ENCODED_POLYLINE_LENGTH = 200000;

function validateRoutePoint(raw, fieldName) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError(`${fieldName} must be an object`);
  }

  return Object.freeze({
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

function validateRoutePreviewInput(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError("route input must be an object");
  }

  const origin = validateRoutePoint(raw.origin, "origin");
  const destination = validateRoutePoint(raw.destination, "destination");

  if (
    Math.abs(origin.latitude - destination.latitude) < 0.00001 &&
    Math.abs(origin.longitude - destination.longitude) < 0.00001
  ) {
    throw new RangeError("pickup and destination cannot be the same");
  }

  return Object.freeze({ origin, destination });
}

function parseGoogleRouteResponse(payload, { includePolyline = false } = {}) {
  const route = payload?.routes?.[0];
  if (
    !route ||
    typeof route.distanceMeters !== "number" ||
    !Number.isFinite(route.distanceMeters) ||
    route.distanceMeters <= 0 ||
    route.distanceMeters > 500000 ||
    typeof route.duration !== "string"
  ) {
    throw new RangeError("Google returned an invalid road route");
  }

  const result = {
    distanceMeters: Math.round(route.distanceMeters),
    durationSeconds: Math.round(
      parseGoogleDurationSeconds(route.duration),
    ),
  };

  if (!includePolyline) return Object.freeze(result);

  const encodedPolyline = route.polyline?.encodedPolyline;
  if (
    typeof encodedPolyline !== "string" ||
    encodedPolyline.length < 2 ||
    encodedPolyline.length > MAX_ENCODED_POLYLINE_LENGTH
  ) {
    throw new RangeError("Google returned an invalid route polyline");
  }

  return Object.freeze({ ...result, encodedPolyline });
}

function advanceRoutePreviewLimit({
  nowMillis,
  windowStartMillis,
  requestCount,
}) {
  if (typeof nowMillis !== "number" || !Number.isFinite(nowMillis)) {
    throw new TypeError("nowMillis must be a finite number");
  }

  const hasActiveWindow =
    typeof windowStartMillis === "number" &&
    Number.isFinite(windowStartMillis) &&
    nowMillis >= windowStartMillis &&
    nowMillis - windowStartMillis < ROUTE_PREVIEW_WINDOW_MS;
  const normalizedCount = Number.isInteger(requestCount) && requestCount > 0
    ? requestCount
    : 0;

  if (!hasActiveWindow) {
    return Object.freeze({
      allowed: true,
      windowStartMillis: nowMillis,
      requestCount: 1,
      retryAfterSeconds: 0,
    });
  }

  if (normalizedCount >= ROUTE_PREVIEW_REQUEST_LIMIT) {
    return Object.freeze({
      allowed: false,
      windowStartMillis,
      requestCount: normalizedCount,
      retryAfterSeconds: Math.max(
        1,
        Math.ceil(
          (ROUTE_PREVIEW_WINDOW_MS - (nowMillis - windowStartMillis)) / 1000,
        ),
      ),
    });
  }

  return Object.freeze({
    allowed: true,
    windowStartMillis,
    requestCount: normalizedCount + 1,
    retryAfterSeconds: 0,
  });
}

module.exports = {
  MAX_ENCODED_POLYLINE_LENGTH,
  ROUTE_PREVIEW_REQUEST_LIMIT,
  ROUTE_PREVIEW_WINDOW_MS,
  advanceRoutePreviewLimit,
  parseGoogleRouteResponse,
  validateRoutePoint,
  validateRoutePreviewInput,
};
