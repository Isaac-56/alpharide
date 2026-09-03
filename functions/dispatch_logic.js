"use strict";

const PRESENCE_FRESH_MS = 90 * 1000;
const DISPATCH_RADIUS_METERS = 12 * 1000;
const MAX_DRIVER_OFFERS = 5;
const OFFER_WINDOW_MS = 45 * 1000;

function normalizeVehicleType(value) {
  if (typeof value !== "string") return "";
  const normalized = value.trim().toLowerCase();

  if (normalized.includes("boda") || normalized.includes("motor")) {
    return "boda";
  }
  if (
    normalized.includes("rickshaw") ||
    normalized.includes("tuk") ||
    normalized.includes("three")
  ) {
    return "rickshaw";
  }
  if (!normalized) return "";
  return "standard";
}

function haversineDistanceMeters(first, second) {
  const earthRadiusMeters = 6371000;
  const toRadians = (degrees) => (degrees * Math.PI) / 180;
  const lat1 = toRadians(first.latitude);
  const lat2 = toRadians(second.latitude);
  const deltaLat = toRadians(second.latitude - first.latitude);
  const deltaLng = toRadians(second.longitude - first.longitude);

  const a =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return earthRadiusMeters * c;
}

function selectPresenceCandidates({
  presenceMap,
  pickup,
  requiredVehicleType,
  nowMs = Date.now(),
  radiusMeters = DISPATCH_RADIUS_METERS,
  limit = MAX_DRIVER_OFFERS,
}) {
  if (!presenceMap || typeof presenceMap !== "object") return [];

  const required = normalizeVehicleType(requiredVehicleType);
  const candidates = [];

  for (const [presenceKey, raw] of Object.entries(presenceMap)) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    if (raw.isOnline !== true) continue;

    const updatedAt = Number(raw.updatedAt);
    if (!Number.isFinite(updatedAt)) continue;
    const ageMs = nowMs - updatedAt;
    if (ageMs < 0 || ageMs > PRESENCE_FRESH_MS) continue;

    const vehicleType = normalizeVehicleType(raw.vehicleType);
    if (!vehicleType || vehicleType !== required) continue;

    const latitude = Number(raw.latitude);
    const longitude = Number(raw.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;
    if (latitude < -90 || latitude > 90) continue;
    if (longitude < -180 || longitude > 180) continue;

    const driverId =
      typeof raw.driverId === "string" && raw.driverId.trim()
        ? raw.driverId.trim()
        : presenceKey;
    if (!driverId) continue;

    const distanceToPickupMeters = haversineDistanceMeters(pickup, {
      latitude,
      longitude,
    });
    if (distanceToPickupMeters > radiusMeters) continue;

    candidates.push({
      driverId,
      vehicleType,
      latitude,
      longitude,
      distanceToPickupMeters: Math.round(distanceToPickupMeters),
      updatedAt,
    });
  }

  candidates.sort(
    (first, second) =>
      first.distanceToPickupMeters - second.distanceToPickupMeters,
  );
  return candidates.slice(0, Math.max(0, limit));
}

function profileAllowsDispatch(profile, requiredVehicleType) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    return false;
  }

  const reviewStatus =
    typeof profile.reviewStatus === "string"
      ? profile.reviewStatus.trim().toLowerCase()
      : "";
  if (reviewStatus !== "approved") return false;

  const registration =
    profile.registration && typeof profile.registration === "object"
      ? profile.registration
      : {};
  const profileVehicleType = normalizeVehicleType(
    registration.vehicleType ?? profile.vehicleType,
  );

  return profileVehicleType === normalizeVehicleType(requiredVehicleType);
}

function validateRideId(value) {
  if (typeof value !== "string") {
    throw new TypeError("rideId must be a string");
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > 160) {
    throw new RangeError("A valid ride ID is required.");
  }
  return normalized;
}

module.exports = {
  DISPATCH_RADIUS_METERS,
  MAX_DRIVER_OFFERS,
  OFFER_WINDOW_MS,
  PRESENCE_FRESH_MS,
  haversineDistanceMeters,
  normalizeVehicleType,
  profileAllowsDispatch,
  selectPresenceCandidates,
  validateRideId,
};
