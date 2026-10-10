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
  ) return "rickshaw";
  if (normalized.includes("scooter")) return "scooter";
  if (normalized.includes("boda") || normalized.includes("motor")) return "boda";
  if (
    normalized === "car" ||
    normalized.includes("sedan") ||
    normalized.includes("hatchback") ||
    normalized.includes("suv") ||
    normalized.includes("4x4") ||
    normalized.includes("minivan") ||
    normalized.includes("mpv") ||
    normalized.includes("pickup")
  ) return "car";
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

function normalizeAdminVehicleClasses(value) {
  const rawValues = Array.isArray(value) ? value : [value];
  return [...new Set(
    rawValues
      .map(normalizeVehicleClass)
      .filter((item) => ADMIN_VEHICLE_CLASSES.includes(item)),
  )].sort(
    (first, second) =>
      ADMIN_VEHICLE_CLASSES.indexOf(first) -
      ADMIN_VEHICLE_CLASSES.indexOf(second),
  );
}

function effectiveVehicleClassesForProfile(profile) {
  const registration = registrationForProfile(profile);
  const rawVehicleType = registration.vehicleType ?? profile?.vehicleType;
  const fixedClass = fixedVehicleClassForBody(rawVehicleType);
  if (fixedClass) return Object.freeze([fixedClass]);

  const assigned = normalizeAdminVehicleClasses(
    registration.vehicleClasses ??
      profile?.vehicleClasses ??
      registration.vehicleClass ??
      profile?.vehicleClass,
  );
  if (assigned.length > 0) return Object.freeze(assigned);

  const hasExplicitAssignment =
    Object.prototype.hasOwnProperty.call(registration, "vehicleClasses") ||
    Object.prototype.hasOwnProperty.call(registration, "vehicleClass") ||
    Object.prototype.hasOwnProperty.call(profile ?? {}, "vehicleClasses") ||
    Object.prototype.hasOwnProperty.call(profile ?? {}, "vehicleClass");
  if (!hasExplicitAssignment && clean(rawVehicleType) === "car") {
    return Object.freeze(["standard"]);
  }
  return Object.freeze([]);
}

function effectiveVehicleClassForProfile(profile) {
  return effectiveVehicleClassesForProfile(profile)[0] ?? "";
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
  return requireAdminVehicleClasses([value])[0];
}

function requireAdminVehicleClasses(value) {
  if (!Array.isArray(value)) {
    throw new TypeError("vehicleClasses must be a list");
  }
  const normalized = normalizeAdminVehicleClasses(value);
  if (normalized.length === 0 || normalized.length !== value.length) {
    throw new TypeError(
      "vehicleClasses must contain one or more unique supported Alpha classes",
    );
  }
  return Object.freeze(normalized);
}

module.exports = {
  ADMIN_VEHICLE_CLASSES,
  effectiveVehicleClassForProfile,
  effectiveVehicleClassesForProfile,
  fixedVehicleClassForBody,
  normalizeAdminVehicleClasses,
  normalizeVehicleBodyType,
  normalizeVehicleClass,
  registrationForProfile,
  requireAdminVehicleClass,
  requireAdminVehicleClasses,
  requiresAdminVehicleClass,
};
