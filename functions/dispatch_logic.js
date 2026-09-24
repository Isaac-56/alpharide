"use strict";

const {
  effectiveVehicleClassForProfile,
  normalizeVehicleClass,
} = require("./vehicle_logic");

const PRESENCE_FRESH_MS = 90 * 1000;
const DISPATCH_RADIUS_METERS = 12 * 1000;
const ACCEPTANCE_PICKUP_RADIUS_METERS = 15 * 1000;
const PRESENCE_CANDIDATE_SCAN_LIMIT = 25;
const MAX_DRIVER_OFFERS = 5;
const OFFER_WINDOW_MS = 45 * 1000;
const DISPATCH_ALGORITHM_VERSION = 2;

function normalizeVehicleType(value) {
  return normalizeVehicleClass(value);
}

function _publicText(value, maximumLength = 80) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maximumLength);
}

function buildDriverPublicSummary(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    return Object.freeze({
      displayName: "Alpha driver",
      firstName: "",
      lastName: "",
      vehicleType: "",
      vehicleClass: "",
      make: "",
      model: "",
      color: "",
      plateNumber: "",
    });
  }

  const registration =
    profile.registration &&
    typeof profile.registration === "object" &&
    !Array.isArray(profile.registration)
      ? profile.registration
      : {};
  const firstName = _publicText(profile.firstName, 60);
  const lastName = _publicText(profile.lastName, 60);
  const displayName = [firstName, lastName].filter(Boolean).join(" ") ||
    "Alpha driver";

  return Object.freeze({
    displayName,
    firstName,
    lastName,
    vehicleType: _publicText(
      registration.vehicleType ?? profile.vehicleType,
      60,
    ),
    vehicleClass: effectiveVehicleClassForProfile(profile),
    make: _publicText(registration.make, 60),
    model: _publicText(registration.model, 60),
    color: _publicText(registration.color, 40),
    plateNumber: _publicText(registration.plateNumber, 40),
  });
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

function presenceAllowsAcceptance({
  presence,
  driverId,
  requiredVehicleType,
  nowMs = Date.now(),
}) {
  if (!presence || typeof presence !== "object" || Array.isArray(presence)) {
    return false;
  }
  if (presence.isOnline !== true) return false;

  const updatedAt = Number(presence.updatedAt);
  if (!Number.isFinite(updatedAt)) return false;
  const ageMs = nowMs - updatedAt;
  if (ageMs < 0 || ageMs > PRESENCE_FRESH_MS) return false;

  const storedDriverId =
    typeof presence.driverId === "string" ? presence.driverId.trim() : "";
  if (storedDriverId && storedDriverId !== driverId) return false;

  return (
    normalizeVehicleType(presence.vehicleType) ===
    normalizeVehicleType(requiredVehicleType)
  );
}

function presenceIsWithinPickupRadius({
  presence,
  pickup,
  radiusMeters = ACCEPTANCE_PICKUP_RADIUS_METERS,
}) {
  if (!presence || typeof presence !== "object" || Array.isArray(presence)) {
    return false;
  }
  if (!pickup || typeof pickup !== "object" || Array.isArray(pickup)) {
    return false;
  }

  const latitude = Number(presence.latitude);
  const longitude = Number(presence.longitude);
  const pickupLatitude = Number(pickup.latitude);
  const pickupLongitude = Number(pickup.longitude);
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    !Number.isFinite(pickupLatitude) ||
    !Number.isFinite(pickupLongitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180 ||
    pickupLatitude < -90 ||
    pickupLatitude > 90 ||
    pickupLongitude < -180 ||
    pickupLongitude > 180 ||
    !Number.isFinite(radiusMeters) ||
    radiusMeters <= 0
  ) {
    return false;
  }

  return (
    haversineDistanceMeters(
      { latitude, longitude },
      { latitude: pickupLatitude, longitude: pickupLongitude },
    ) <= radiusMeters
  );
}

function selectPresenceCandidates({
  presenceMap,
  pickup,
  requiredVehicleType,
  nowMs = Date.now(),
  radiusMeters = DISPATCH_RADIUS_METERS,
  limit = PRESENCE_CANDIDATE_SCAN_LIMIT,
}) {
  if (!presenceMap || typeof presenceMap !== "object") return [];

  const required = normalizeVehicleType(requiredVehicleType);
  const candidates = [];

  for (const [presenceKey, raw] of Object.entries(presenceMap)) {
    const driverId =
      raw && typeof raw.driverId === "string" && raw.driverId.trim()
        ? raw.driverId.trim()
        : presenceKey;

    if (
      !presenceAllowsAcceptance({
        presence: raw,
        driverId,
        requiredVehicleType: required,
        nowMs,
      })
    ) {
      continue;
    }

    const latitude = Number(raw.latitude);
    const longitude = Number(raw.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;
    if (latitude < -90 || latitude > 90) continue;
    if (longitude < -180 || longitude > 180) continue;

    const distanceToPickupMeters = haversineDistanceMeters(pickup, {
      latitude,
      longitude,
    });
    if (distanceToPickupMeters > radiusMeters) continue;

    candidates.push({
      driverId,
      vehicleType: normalizeVehicleType(raw.vehicleType),
      latitude,
      longitude,
      distanceToPickupMeters: Math.round(distanceToPickupMeters),
      updatedAt: Number(raw.updatedAt),
    });
  }

  candidates.sort(
    (first, second) => {
      const distance =
        first.distanceToPickupMeters - second.distanceToPickupMeters;
      if (distance !== 0) return distance;

      const freshness = second.updatedAt - first.updatedAt;
      if (freshness !== 0) return freshness;

      return first.driverId.localeCompare(second.driverId);
    },
  );
  return candidates.slice(0, Math.max(0, limit));
}

function selectEligibleDispatchCandidates({
  presenceCandidates,
  profilesByDriverId,
  busyDriverIds = [],
  requiredVehicleType,
  limit = MAX_DRIVER_OFFERS,
}) {
  if (!Array.isArray(presenceCandidates)) return [];

  const profiles =
    profilesByDriverId && typeof profilesByDriverId === "object"
      ? profilesByDriverId
      : {};
  const busy = new Set(Array.isArray(busyDriverIds) ? busyDriverIds : []);

  return presenceCandidates
    .filter((candidate) => {
      const driverId =
        candidate && typeof candidate.driverId === "string"
          ? candidate.driverId
          : "";
      return (
        driverId &&
        !busy.has(driverId) &&
        profileAllowsDispatch(profiles[driverId], requiredVehicleType)
      );
    })
    .slice(0, Math.max(0, limit));
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

  const profileVehicleType = effectiveVehicleClassForProfile(profile);
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
  ACCEPTANCE_PICKUP_RADIUS_METERS,
  DISPATCH_ALGORITHM_VERSION,
  DISPATCH_RADIUS_METERS,
  MAX_DRIVER_OFFERS,
  OFFER_WINDOW_MS,
  PRESENCE_CANDIDATE_SCAN_LIMIT,
  PRESENCE_FRESH_MS,
  buildDriverPublicSummary,
  haversineDistanceMeters,
  normalizeVehicleType,
  presenceAllowsAcceptance,
  presenceIsWithinPickupRadius,
  profileAllowsDispatch,
  selectEligibleDispatchCandidates,
  selectPresenceCandidates,
  validateRideId,
};
