"use strict";

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function normalizedPhone(value) {
  return text(value).replace(/[\s()-]/g, "");
}

function driverReviewPayload({
  driverId,
  profile,
  authenticatedPhoneNumber,
}) {
  const safeProfile = object(profile);
  const registration = object(safeProfile.registration);
  const documents = object(safeProfile.documents);
  const licence = object(documents.driverLicence);
  const frontStoragePath = text(licence.frontStoragePath);
  const backStoragePath = text(licence.backStoragePath);
  const documentPrefix = `drivers/${driverId}/documents/driver_licence/`;
  const phoneNumber = text(safeProfile.phoneNumber);
  const verifiedPhone = normalizedPhone(authenticatedPhoneNumber);
  const phoneVerified = verifiedPhone.length > 0 &&
    verifiedPhone === normalizedPhone(phoneNumber);

  const checks = [
    {
      key: "phone",
      label: "Firebase phone number verified",
      passed: phoneVerified,
    },
    {
      key: "identity",
      label: "Driver identity completed",
      passed: text(safeProfile.firstName).length >= 2 &&
        text(safeProfile.lastName).length >= 2,
    },
    {
      key: "service",
      label: "Ride service selected",
      passed: text(registration.serviceType) === "rides",
    },
    {
      key: "vehicle",
      label: "Vehicle information completed",
      passed: [
        "vehicleType",
        "make",
        "model",
        "color",
        "manufactureYear",
        "plateNumber",
      ].every((field) => text(registration[field]).length > 0),
    },
    {
      key: "licence",
      label: "Driver licence information completed",
      passed: [
        "licenceCountry",
        "licenceFirstName",
        "licenceLastName",
        "licenceNumber",
        "licenceIssueDate",
      ].every((field) => text(registration[field]).length > 0),
    },
    {
      key: "documents",
      label: "Front and back licence images uploaded",
      passed: licence.status === "uploaded" &&
        licence.qualityChecked === true &&
        frontStoragePath.startsWith(documentPrefix) &&
        backStoragePath.startsWith(documentPrefix),
    },
    {
      key: "onboarding",
      label: "Alpha Plus registration submitted",
      passed: safeProfile.onboardingCompleted === true,
    },
  ];

  return {
    driverId,
    identity: {
      firstName: text(safeProfile.firstName),
      lastName: text(safeProfile.lastName),
      phoneNumber,
      phoneVerified,
    },
    registration: {
      serviceType: text(registration.serviceType),
      vehicleType: text(registration.vehicleType),
      vehicleClass: text(registration.vehicleClass),
      make: text(registration.make),
      model: text(registration.model),
      color: text(registration.color),
      manufactureYear: text(registration.manufactureYear),
      plateNumber: text(registration.plateNumber),
      licenceCountry: text(registration.licenceCountry),
      licenceFirstName: text(registration.licenceFirstName),
      licenceLastName: text(registration.licenceLastName),
      licenceNumber: text(registration.licenceNumber),
      licenceIssueDate: text(registration.licenceIssueDate),
    },
    documents: {
      driverLicence: {
        status: text(licence.status),
        qualityChecked: licence.qualityChecked === true,
        frontStoragePath,
        backStoragePath,
      },
    },
    onboardingCompleted: safeProfile.onboardingCompleted === true,
    reviewStatus: text(safeProfile.reviewStatus) || "pending",
    reviewNote: text(safeProfile.reviewNote),
    checks,
    readyForApproval: checks.every((check) => check.passed),
    missingRequirements: checks
      .filter((check) => !check.passed)
      .map((check) => check.label),
  };
}

module.exports = { driverReviewPayload, normalizedPhone };
