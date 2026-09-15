"use strict";

const { createHash } = require("node:crypto");

const ACCOUNT_ROLES = new Set(["passenger", "driver"]);

function normalizeAccountRole(value) {
  if (typeof value !== "string") {
    throw new TypeError("Account role must be a string.");
  }

  const role = value.trim().toLowerCase();
  if (!ACCOUNT_ROLES.has(role)) {
    throw new TypeError("Account role must be passenger or driver.");
  }
  return role;
}

function hashPhoneNumber(phoneNumber) {
  if (typeof phoneNumber !== "string" || !phoneNumber.trim()) {
    throw new TypeError("A verified phone number is required.");
  }

  return createHash("sha256")
    .update(`alpha-account-role:v1:${phoneNumber.trim()}`)
    .digest("hex");
}

function inferExistingRole({
  accountRole = null,
  identityRole = null,
  passengerExists = false,
  legacyPassengerExists = false,
  driverExists = false,
} = {}) {
  const roles = new Set();

  for (const candidate of [accountRole, identityRole]) {
    if (candidate == null || candidate === "") continue;
    roles.add(normalizeAccountRole(candidate));
  }

  if (passengerExists || legacyPassengerExists) {
    roles.add("passenger");
  }
  if (driverExists) {
    roles.add("driver");
  }

  if (roles.size > 1) {
    throw new RangeError(
      "Conflicting passenger and driver account records already exist.",
    );
  }

  return roles.size === 1 ? [...roles][0] : null;
}

function roleConflictMessage(existingRole, desiredRole) {
  const existing = normalizeAccountRole(existingRole);
  const desired = normalizeAccountRole(desiredRole);

  if (existing === desired) {
    return "";
  }

  if (existing === "driver") {
    return "This phone number is already registered with Alpha Plus. Use a different number for AlphaRide.";
  }

  return "This phone number is already registered with AlphaRide. Use a different number for Alpha Plus.";
}

module.exports = {
  hashPhoneNumber,
  inferExistingRole,
  normalizeAccountRole,
  roleConflictMessage,
};
