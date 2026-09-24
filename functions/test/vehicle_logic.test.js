"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  effectiveVehicleClassForProfile,
  fixedVehicleClassForBody,
  normalizeVehicleBodyType,
  normalizeVehicleClass,
  requireAdminVehicleClass,
  requiresAdminVehicleClass,
} = require("../vehicle_logic");

test("South Sudan registration bodies normalize without choosing a car tier", () => {
  assert.equal(normalizeVehicleBodyType("Sedan"), "car");
  assert.equal(normalizeVehicleBodyType("SUV / 4x4"), "car");
  assert.equal(normalizeVehicleBodyType("Minivan / MPV"), "car");
  assert.equal(normalizeVehicleBodyType("Boda boda (motorcycle)"), "boda");
  assert.equal(
    normalizeVehicleBodyType("Bajaj / Tuk-tuk (three-wheeler)"),
    "rickshaw",
  );
  assert.equal(normalizeVehicleBodyType("Scooter"), "scooter");
  assert.equal(normalizeVehicleClass("Sedan"), "");
});

test("boda, scooter and three-wheeler classes are fixed", () => {
  assert.equal(fixedVehicleClassForBody("Boda boda (motorcycle)"), "boda");
  assert.equal(fixedVehicleClassForBody("Scooter"), "boda");
  assert.equal(
    fixedVehicleClassForBody("Bajaj / Tuk-tuk (three-wheeler)"),
    "rickshaw",
  );
});

test("regular cars require an administrator service class", () => {
  const profile = {
    registration: {
      vehicleType: "SUV / 4x4",
      vehicleClass: "",
    },
  };

  assert.equal(requiresAdminVehicleClass(profile), true);
  assert.equal(effectiveVehicleClassForProfile(profile), "");

  profile.registration.vehicleClass = "comfort";
  assert.equal(effectiveVehicleClassForProfile(profile), "comfort");
});

test("legacy Car profiles remain standard until an administrator changes them", () => {
  assert.equal(
    effectiveVehicleClassForProfile({
      registration: { vehicleType: "Car" },
    }),
    "standard",
  );
});

test("administrator classes reject fixed or unknown values", () => {
  assert.equal(requireAdminVehicleClass(" Premium "), "premium");
  assert.throws(() => requireAdminVehicleClass("boda"), /vehicleClass/);
  assert.throws(() => requireAdminVehicleClass("sedan"), /vehicleClass/);
});
