"use strict";

const ADMIN_VEHICLE_CLASSES = Object.freeze([
  "standard",
  "comfort",
  "ev",
  "premium",
  "corporate",
]);

function clean(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function normalizeVehicleBodyType(value) {
  const normalized = clean(value);
  if (!normalized) return "";

  if (
    normalized.includes("rickshaw") ||
    normalized.includes("tuk") ||
    normalized.includes("three") ||
    normalized.includes("bajaj")
  ) {
    return "rickshaw";
  }
  if (normalized.includes("scooter")) return "scooter";
  if (normalized.includes("boda") || normalized.includes("motor")) {
    return "boda";
  }
  if (
    normalized === "car" ||
    normalized.includes("sedan") ||
    normalized.includes("hatchback") ||
    normalized.includes("suv") ||
    normalized.includes("4x4") ||
    normalized.includes("minivan") ||
    normalized.includes("mpv") ||
    normalized.includes("pickup")
  ) {
    return "car";
  }

  return "";
}

function normalizeVehicleClass(value) {
  const normalized = clean(value);
  if (!normalized) return "";

  if (ADMIN_VEHICLE_CLASSES.includes(normalized)) return normalized;
  if (normalized.includes("electric")) return "ev";

  const bodyType = normalizeVehicleBodyType(normalized);
  if (bodyType === "rickshaw") return "rickshaw";
  if (bodyType === "boda" || bodyType === "scooter") return "boda";

  // Kept only for driver-location records and profiles created before the
  // separate administrator vehicle class was introduced.
  if (normalized === "car") return "standard";

  return "";
}

function fixedVehicleClassForBody(value) {
  const bodyType = normalizeVehicleBodyType(value);
  if (bodyType === "rickshaw") return "rickshaw";
  if (bodyType === "boda" || bodyType === "scooter") return "boda";
  return "";
}

function registrationForProfile(profile) {
  return profile?.registration &&
    typeof profile.registration === "object" &&
    !Array.isArray(profile.registration)
    ? profile.registration
    : {};
}

function effectiveVehicleClassForProfile(profile) {
  const registration = registrationForProfile(profile);
  const rawVehicleType = registration.vehicleType ?? profile?.vehicleType;
  const fixedClass = fixedVehicleClassForBody(rawVehicleType);
  if (fixedClass) return fixedClass;

  const assignedClass = normalizeVehicleClass(
    registration.vehicleClass ?? profile?.vehicleClass,
  );
  if (ADMIN_VEHICLE_CLASSES.includes(assignedClass)) return assignedClass;

  const legacyCar =
    !Object.prototype.hasOwnProperty.call(registration, "vehicleClass") &&
    clean(rawVehicleType) === "car";
  return legacyCar ? "standard" : "";
}

function requiresAdminVehicleClass(profile) {
  const registration = registrationForProfile(profile);
  const vehicleType = registration.vehicleType ?? profile?.vehicleType;
  return (
    normalizeVehicleBodyType(vehicleType) === "car" &&
    fixedVehicleClassForBody(vehicleType) === ""
  );
}

function requireAdminVehicleClass(value) {
  const normalized = normalizeVehicleClass(value);
  if (!ADMIN_VEHICLE_CLASSES.includes(normalized)) {
    throw new TypeError(
      "vehicleClass must be standard, comfort, ev, premium or corporate",
    );
  }
  return normalized;
}

module.exports = {
  ADMIN_VEHICLE_CLASSES,
  effectiveVehicleClassForProfile,
  fixedVehicleClassForBody,
  normalizeVehicleBodyType,
  normalizeVehicleClass,
  registrationForProfile,
  requireAdminVehicleClass,
  requiresAdminVehicleClass,
};
