"use strict";

const JUBA_UTC_OFFSET_MILLIS = 2 * 60 * 60 * 1000;

function buildReceiptNumber({ rideId, completedAtMillis }) {
  if (typeof rideId !== "string" || !/^[A-Za-z0-9_-]{6,128}$/.test(rideId)) {
    throw new TypeError("rideId is required for the receipt number");
  }
  if (!Number.isFinite(completedAtMillis) || completedAtMillis <= 0) {
    throw new TypeError("completedAtMillis is required for the receipt number");
  }

  const jubaDate = new Date(completedAtMillis + JUBA_UTC_OFFSET_MILLIS);
  const year = jubaDate.getUTCFullYear();
  const month = String(jubaDate.getUTCMonth() + 1).padStart(2, "0");
  const day = String(jubaDate.getUTCDate()).padStart(2, "0");
  const suffix = rideId.replace(/[^A-Za-z0-9]/g, "").toUpperCase().slice(-10);
  return `AR-${year}${month}${day}-${suffix}`;
}

module.exports = { JUBA_UTC_OFFSET_MILLIS, buildReceiptNumber };
