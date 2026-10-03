"use strict";

const { createHash } = require("node:crypto");
const { validateCreateRideInput } = require("./ride_logic");

const CALL_CENTER_BOOKING_SOURCE = "call_center";
const SOUTH_SUDAN_COUNTRY_CODE = "211";
const MAX_CUSTOMER_NAME_LENGTH = 80;
const MAX_BOOKING_NOTE_LENGTH = 180;
const MAX_PLACE_QUERY_LENGTH = 120;

function normalizeSouthSudanPhone(value) {
  if (typeof value !== "string") {
    throw new TypeError("customerPhone must be a string");
  }

  let phone = value.trim().replace(/[\s().-]/g, "");
  if (phone.startsWith("00")) phone = `+${phone.slice(2)}`;
  if (phone.startsWith("0")) phone = `+${SOUTH_SUDAN_COUNTRY_CODE}${phone.slice(1)}`;
  if (phone.startsWith(SOUTH_SUDAN_COUNTRY_CODE)) phone = `+${phone}`;

  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    throw new RangeError(
      "Enter a valid phone number, for example +211 92 123 4567.",
    );
  }
  return phone;
}

function normalizeCustomerName(value) {
  if (typeof value !== "string") {
    throw new TypeError("customerName must be a string");
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > MAX_CUSTOMER_NAME_LENGTH) {
    throw new RangeError(
      `customerName must contain between 1 and ${MAX_CUSTOMER_NAME_LENGTH} characters`,
    );
  }
  return normalized;
}

function normalizeBookingNote(value) {
  if (value == null || value === "") return "";
  if (typeof value !== "string") {
    throw new TypeError("customerNote must be a string");
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length > MAX_BOOKING_NOTE_LENGTH) {
    throw new RangeError(
      `customerNote cannot exceed ${MAX_BOOKING_NOTE_LENGTH} characters`,
    );
  }
  return normalized;
}

function validateCallCenterRideInput(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new TypeError("phone booking input must be an object");
  }
  const ride = validateCreateRideInput({
    pickup: raw.pickup,
    destination: raw.destination,
    rideOptionId: raw.rideOptionId,
    paymentMethod: "cash",
  });
  return Object.freeze({
    ...ride,
    customerName: normalizeCustomerName(raw.customerName),
    customerPhone: normalizeSouthSudanPhone(raw.customerPhone),
    customerNote: normalizeBookingNote(raw.customerNote),
  });
}

function callCenterPassengerId(phone) {
  const normalized = normalizeSouthSudanPhone(phone);
  return `call_${createHash("sha256").update(normalized).digest("hex").slice(0, 40)}`;
}

function maskPhoneNumber(phone) {
  const normalized = normalizeSouthSudanPhone(phone);
  return `${normalized.slice(0, 5)}••••${normalized.slice(-3)}`;
}

function validatePlaceSearchQuery(value) {
  if (typeof value !== "string") {
    throw new TypeError("query must be a string");
  }
  const query = value.trim().replace(/\s+/g, " ");
  if (query.length < 2 || query.length > MAX_PLACE_QUERY_LENGTH) {
    throw new RangeError(
      `query must contain between 2 and ${MAX_PLACE_QUERY_LENGTH} characters`,
    );
  }
  return query;
}

function validatePlaceId(value) {
  if (typeof value !== "string") throw new TypeError("placeId must be a string");
  const placeId = value.trim();
  if (!/^[A-Za-z0-9_-]{8,300}$/.test(placeId)) {
    throw new RangeError("placeId is invalid");
  }
  return placeId;
}

function parseGooglePlacePredictions(payload) {
  const suggestions = Array.isArray(payload?.suggestions)
    ? payload.suggestions
    : [];
  return suggestions
    .map((suggestion) => suggestion?.placePrediction)
    .filter((prediction) => prediction && typeof prediction === "object")
    .map((prediction) => ({
      placeId: typeof prediction.placeId === "string"
        ? prediction.placeId.trim()
        : "",
      primaryText:
        typeof prediction.structuredFormat?.mainText?.text === "string"
          ? prediction.structuredFormat.mainText.text.trim()
          : "",
      secondaryText:
        typeof prediction.structuredFormat?.secondaryText?.text === "string"
          ? prediction.structuredFormat.secondaryText.text.trim()
          : "",
      description: typeof prediction.text?.text === "string"
        ? prediction.text.text.trim()
        : "",
    }))
    .filter((prediction) => prediction.placeId && prediction.description)
    .slice(0, 8);
}

function parseGooglePlaceDetails(payload, placeId) {
  const latitude = payload?.location?.latitude;
  const longitude = payload?.location?.longitude;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new RangeError("Google Places returned no map point");
  }
  const formattedAddress = typeof payload.formattedAddress === "string"
    ? payload.formattedAddress.trim()
    : "";
  const displayName = typeof payload.displayName?.text === "string"
    ? payload.displayName.text.trim()
    : "";
  const address = formattedAddress || displayName;
  if (!address) throw new RangeError("Google Places returned no address");
  return Object.freeze({ placeId, address, latitude, longitude });
}

module.exports = {
  CALL_CENTER_BOOKING_SOURCE,
  callCenterPassengerId,
  maskPhoneNumber,
  normalizeBookingNote,
  normalizeCustomerName,
  normalizeSouthSudanPhone,
  parseGooglePlaceDetails,
  parseGooglePlacePredictions,
  validateCallCenterRideInput,
  validatePlaceId,
  validatePlaceSearchQuery,
};
