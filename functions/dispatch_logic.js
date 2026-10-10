"use strict";

const {
  effectiveVehicleClassForProfile,
  effectiveVehicleClassesForProfile,
  normalizeVehicleClass,
} = require("./vehicle_logic");

const PRESENCE_FRESH_MS = 90 * 1000;
const DISPATCH_RADIUS_METERS = 12 * 1000;
const ACCEPTANCE_PICKUP_RADIUS_METERS = 15 * 1000;
const PRESENCE_CANDIDATE_SCAN_LIMIT = 25;
const MAX_DRIVER_OFFERS = 5;
const OFFER_WINDOW_MS = 30 * 1000;
const DISPATCH_ALGORITHM_VERSION = 3;

function normalizeVehicleType(value) {
  return normalizeVehicleClass(value);
}

function _publicText(value, maximumLength = 80) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maximumLength);
}

function _publicPhone(value) {
  const phoneNumber = _publicText(value, 20).replace(/\s+/g, "");
  return /^\+[1-9]\d{7,14}$/.test(phoneNumber) ? phoneNumber : "";
}

function buildDriverPublicSummary(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    return Object.freeze({
      displayName: "Alpha driver",
      firstName: "",
      lastName: "",
      vehicleType: "",
      vehicleClass: "",
      vehicleClasses: [],
      make: "",
      model: "",
      color: "",
      plateNumber: "",
      phoneNumber: "",
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
    vehicleClasses: effectiveVehicleClassesForProfile(profile),
    make: _publicText(registration.make, 60),
    model: _publicText(registration.model, 60),
    color: _publicText(registration.color, 40),
    plateNumber: _publicText(registration.plateNumber, 40),
    phoneNumber: _publicPhone(profile.phoneNumber),
  });
}

function approvedDriverPhotoStoragePath({ ride, passengerId, photoCheck }) {
  if (!ride || typeof ride !== "object" || Array.isArray(ride)) return "";
  if (!photoCheck || typeof photoCheck !== "object" || Array.isArray(photoCheck)) {
    return "";
  }

  const normalizedPassengerId = _publicText(passengerId, 160);
  const ridePassengerId = _publicText(ride.passengerId, 160);
  const driverId = _publicText(ride.driverId, 160);
  const rideStatus = _publicText(ride.status, 40).toLowerCase();
  const activeStatuses = new Set([
    "accepted",
    "driver_arriving",
    "arrived",
    "in_progress",
  ]);

  if (
    !normalizedPassengerId ||
    normalizedPassengerId !== ridePassengerId ||
    !driverId ||
    !activeStatuses.has(rideStatus) ||
    _publicText(photoCheck.status, 40).toLowerCase() !== "approved"
  ) {
    return "";
  }

  const photoDriverId = _publicText(photoCheck.driverId, 160);
  if (photoDriverId && photoDriverId !== driverId) return "";

  const storagePath = _publicText(photoCheck.storagePath, 500);
  const requiredPrefix = `drivers/${driverId}/documents/photo_checks/`;
  if (!storagePath.startsWith(requiredPrefix)) return "";
  if (!/\.(?:jpe?g|png|webp)$/i.test(storagePath)) return "";

  return storagePath;
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
  const rawOnline = presence.isOnline ?? presence.online;
  const isOnline = rawOnline === true || rawOnline === 1 ||
    (typeof rawOnline === "string" &&
      ["true", "online", "1"].includes(rawOnline.trim().toLowerCase()));
  if (!isOnline) return false;

  const updatedAt = Number(presence.updatedAt ?? presence.lastUpdated);
  if (!Number.isFinite(updatedAt)) return false;
  const ageMs = nowMs - updatedAt;
  if (ageMs < 0 || ageMs > PRESENCE_FRESH_MS) return false;

  const storedDriverId =
    typeof presence.driverId === "string" ? presence.driverId.trim() : "";
  if (storedDriverId && storedDriverId !== driverId) return false;

  const activeRideId =
    typeof presence.activeRideId === "string"
      ? presence.activeRideId.trim()
      : "";
  return activeRideId === "";
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
  excludedDriverIds = [],
}) {
  if (!presenceMap || typeof presenceMap !== "object") return [];

  const required = normalizeVehicleType(requiredVehicleType);
  const candidates = [];
  const excluded = new Set(excludedDriverIds);

  for (const [presenceKey, raw] of Object.entries(presenceMap)) {
    const driverId =
      raw && typeof raw.driverId === "string" && raw.driverId.trim()
        ? raw.driverId.trim()
        : presenceKey;

    if (
      excluded.has(driverId) ||
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

    const presenceVehicleType = normalizeVehicleType(
      raw.vehicleType ?? raw.vehicleClass,
    );
    candidates.push({
      driverId,
      vehicleType: presenceVehicleType,
      presenceVehicleMatches:
        Boolean(required) && presenceVehicleType === required,
      latitude,
      longitude,
      distanceToPickupMeters: Math.round(distanceToPickupMeters),
      updatedAt: Number(raw.updatedAt),
    });
  }

  candidates.sort(
    (first, second) => {
      // Presence is public and therefore not authoritative for acceptance,
      // but prioritising the requested class prevents a nearby fleet of cars
      // from pushing a valid Boda/Rickshaw beyond the verification scan.
      const vehicleMatch = Number(second.presenceVehicleMatches) -
        Number(first.presenceVehicleMatches);
      if (vehicleMatch !== 0) return vehicleMatch;

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

  const profileVehicleTypes = effectiveVehicleClassesForProfile(profile);
  return profileVehicleTypes.includes(
    normalizeVehicleType(requiredVehicleType),
  );
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
  approvedDriverPhotoStoragePath,
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
