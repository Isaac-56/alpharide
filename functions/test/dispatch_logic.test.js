"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCEPTANCE_PICKUP_RADIUS_METERS,
  DISPATCH_RADIUS_METERS,
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
} = require("../dispatch_logic");

test("vehicle types normalize to the shared launch contract", () => {
  assert.equal(normalizeVehicleType("Motorbike"), "boda");
  assert.equal(normalizeVehicleType("Tuk Tuk"), "rickshaw");
  assert.equal(normalizeVehicleType("Car"), "standard");
});

test("candidate selection keeps fresh matching nearby drivers sorted", () => {
  const nowMs = 1_800_000_000_000;
  const pickup = { latitude: 4.8517, longitude: 31.5825 };
  const candidates = selectPresenceCandidates({
    nowMs,
    pickup,
    requiredVehicleType: "standard",
    presenceMap: {
      near: {
        driverId: "near",
        isOnline: true,
        vehicleType: "standard",
        latitude: 4.8520,
        longitude: 31.5830,
        updatedAt: nowMs - 1000,
      },
      farther: {
        driverId: "farther",
        isOnline: true,
        vehicleType: "standard",
        latitude: 4.86,
        longitude: 31.59,
        updatedAt: nowMs - 2000,
      },
      stale: {
        driverId: "stale",
        isOnline: true,
        vehicleType: "standard",
        latitude: 4.852,
        longitude: 31.583,
        updatedAt: nowMs - PRESENCE_FRESH_MS - 1,
      },
      wrongType: {
        driverId: "wrongType",
        isOnline: true,
        vehicleType: "boda",
        latitude: 4.852,
        longitude: 31.583,
        updatedAt: nowMs - 1000,
      },
      offline: {
        driverId: "offline",
        isOnline: false,
        vehicleType: "standard",
        latitude: 4.852,
        longitude: 31.583,
        updatedAt: nowMs - 1000,
      },
    },
  });

  assert.deepEqual(
    candidates.map((candidate) => candidate.driverId),
    ["near", "farther"],
  );
  assert.ok(
    candidates[0].distanceToPickupMeters <
      candidates[1].distanceToPickupMeters,
  );
});

test("drivers outside the dispatch radius are excluded", () => {
  const pickup = { latitude: 4.8517, longitude: 31.5825 };
  const distant = { latitude: 5.1, longitude: 31.9 };
  assert.ok(haversineDistanceMeters(pickup, distant) > DISPATCH_RADIUS_METERS);
});

test("acceptance location must remain near the passenger pickup", () => {
  const pickup = { latitude: 4.8517, longitude: 31.5825 };

  assert.equal(
    presenceIsWithinPickupRadius({
      presence: { latitude: 4.852, longitude: 31.583 },
      pickup,
    }),
    true,
  );
  assert.equal(
    presenceIsWithinPickupRadius({
      presence: { latitude: 5.1, longitude: 31.9 },
      pickup,
      radiusMeters: ACCEPTANCE_PICKUP_RADIUS_METERS,
    }),
    false,
  );
});

test("acceptance requires current online matching presence", () => {
  const nowMs = 1_800_000_000_000;
  const valid = {
    driverId: "driver-1",
    isOnline: true,
    vehicleType: "Car",
    updatedAt: nowMs - 1000,
  };

  assert.equal(
    presenceAllowsAcceptance({
      presence: valid,
      driverId: "driver-1",
      requiredVehicleType: "standard",
      nowMs,
    }),
    true,
  );
  assert.equal(
    presenceAllowsAcceptance({
      presence: { ...valid, isOnline: false },
      driverId: "driver-1",
      requiredVehicleType: "standard",
      nowMs,
    }),
    false,
  );
  assert.equal(
    presenceAllowsAcceptance({
      presence: { ...valid, updatedAt: nowMs - PRESENCE_FRESH_MS - 1 },
      driverId: "driver-1",
      requiredVehicleType: "standard",
      nowMs,
    }),
    false,
  );
  assert.equal(
    presenceAllowsAcceptance({
      presence: { ...valid, vehicleType: "Boda" },
      driverId: "driver-1",
      requiredVehicleType: "standard",
      nowMs,
    }),
    false,
  );
});

test("driver profile must be approved and vehicle matched", () => {
  assert.equal(
    profileAllowsDispatch(
      {
        reviewStatus: "approved",
        registration: { vehicleType: "Car" },
      },
      "standard",
    ),
    true,
  );
  assert.equal(
    profileAllowsDispatch(
      {
        reviewStatus: "pending",
        registration: { vehicleType: "Car" },
      },
      "standard",
    ),
    false,
  );
  assert.equal(
    profileAllowsDispatch(
      {
        reviewStatus: "approved",
        registration: { vehicleType: "Motorbike" },
      },
      "standard",
    ),
    false,
  );
});

test("dispatch skips unapproved and busy drivers before applying offer limit", () => {
  const presenceCandidates = Array.from({ length: 8 }, (_, index) => ({
    driverId: `driver-${index + 1}`,
    distanceToPickupMeters: (index + 1) * 100,
    updatedAt: 1_800_000_000_000 - index,
  }));
  const profilesByDriverId = Object.fromEntries(
    presenceCandidates.map((candidate, index) => [
      candidate.driverId,
      {
        reviewStatus: index < 5 ? "pending" : "approved",
        registration: { vehicleType: "Car" },
      },
    ]),
  );

  assert.deepEqual(
    selectEligibleDispatchCandidates({
      presenceCandidates,
      profilesByDriverId,
      busyDriverIds: ["driver-6"],
      requiredVehicleType: "standard",
    }).map((candidate) => candidate.driverId),
    ["driver-7", "driver-8"],
  );
});

test("equal-distance candidates prefer fresher presence deterministically", () => {
  const pickup = { latitude: 4.8517, longitude: 31.5825 };
  const candidates = selectPresenceCandidates({
    nowMs: 1_800_000_000_000,
    pickup,
    requiredVehicleType: "standard",
    presenceMap: {
      older: {
        driverId: "older",
        isOnline: true,
        vehicleType: "standard",
        latitude: pickup.latitude,
        longitude: pickup.longitude,
        updatedAt: 1_799_999_999_000,
      },
      newer: {
        driverId: "newer",
        isOnline: true,
        vehicleType: "standard",
        latitude: pickup.latitude,
        longitude: pickup.longitude,
        updatedAt: 1_799_999_999_500,
      },
    },
  });

  assert.deepEqual(
    candidates.map((candidate) => candidate.driverId),
    ["newer", "older"],
  );
});

test("public driver summary exposes rider-safe identity and vehicle fields", () => {
  assert.deepEqual(
    buildDriverPublicSummary({
      firstName: "  Daniel ",
      lastName: " Driver ",
      phoneNumber: "+211900000000",
      registration: {
        vehicleType: "Car",
        make: "Toyota",
        model: "Corolla",
        color: "White",
        plateNumber: "SSD 1234",
        licenceNumber: "PRIVATE-LICENCE",
      },
    }),
    {
      displayName: "Daniel Driver",
      firstName: "Daniel",
      lastName: "Driver",
      vehicleType: "Car",
      make: "Toyota",
      model: "Corolla",
      color: "White",
      plateNumber: "SSD 1234",
    },
  );
});

test("public driver summary falls back safely when profile data is absent", () => {
  assert.deepEqual(buildDriverPublicSummary(null), {
    displayName: "Alpha driver",
    firstName: "",
    lastName: "",
    vehicleType: "",
    make: "",
    model: "",
    color: "",
    plateNumber: "",
  });
});

test("ride ids are validated before callable actions", () => {
  assert.equal(validateRideId(" ride-123 "), "ride-123");
  assert.throws(() => validateRideId("   "), /valid ride ID/);
});
