"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { driverReviewPayload } = require("../driver_review_logic");

function completeProfile(driverId = "driver-1") {
  return {
    firstName: "Ada",
    lastName: "Driver",
    phoneNumber: "+211912345678",
    onboardingCompleted: true,
    reviewStatus: "pending",
    registration: {
      serviceType: "rides",
      vehicleType: "Boda boda (motorcycle)",
      vehicleClass: "",
      make: "Senke",
      model: "SK 125",
      color: "Red",
      manufactureYear: "2025",
      plateNumber: "SSD 123 A",
      licenceCountry: "South Sudan",
      licenceFirstName: "Ada",
      licenceLastName: "Driver",
      licenceNumber: "DL-12345",
      licenceIssueDate: "2026-01-10",
    },
    documents: {
      driverLicence: {
        status: "uploaded",
        qualityChecked: true,
        frontStoragePath:
          `drivers/${driverId}/documents/driver_licence/front.jpg`,
        backStoragePath:
          `drivers/${driverId}/documents/driver_licence/back.jpg`,
      },
    },
  };
}

test("complete Firebase-verified driver registration is approval ready", () => {
  const result = driverReviewPayload({
    driverId: "driver-1",
    profile: completeProfile(),
    authenticatedPhoneNumber: "+211 912 345 678",
  });

  assert.equal(result.readyForApproval, true);
  assert.equal(result.identity.phoneVerified, true);
  assert.deepEqual(result.missingRequirements, []);
  assert.equal(result.registration.vehicleType, "Boda boda (motorcycle)");
});

test("approval stays blocked until licence images and OTP identity are valid", () => {
  const profile = completeProfile();
  profile.documents.driverLicence.backStoragePath =
    "drivers/another-driver/documents/driver_licence/back.jpg";

  const result = driverReviewPayload({
    driverId: "driver-1",
    profile,
    authenticatedPhoneNumber: "+211900000000",
  });

  assert.equal(result.readyForApproval, false);
  assert.equal(result.identity.phoneVerified, false);
  assert.deepEqual(result.missingRequirements, [
    "Firebase phone number verified",
    "Front and back licence images uploaded",
  ]);
});
