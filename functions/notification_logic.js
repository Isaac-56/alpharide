"use strict";

function validatePushToken(value) {
  if (typeof value !== "string") {
    throw new TypeError("A notification token is required.");
  }
  const token = value.trim();
  if (token.length < 20 || token.length > 4096) {
    throw new RangeError("The notification token is invalid.");
  }
  return token;
}

function rideLabel(rideOptionId) {
  const normalized = typeof rideOptionId === "string"
    ? rideOptionId.trim().toLowerCase()
    : "";
  if (normalized === "boda") return "Boda";
  if (normalized === "rickshaw") return "Rickshaw";
  if (!normalized) return "Alpha";
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

function buildRideOfferMessage({
  token,
  rideId,
  rideOptionId,
  pickupAddress,
  estimatedFare,
  currencyCode,
}) {
  return {
    token: validatePushToken(token),
    notification: {
      title: `New ${rideLabel(rideOptionId)} ride request`,
      body: `${pickupAddress} · ${estimatedFare} ${currencyCode}`,
    },
    data: { type: "ride_offer", rideId, rideOptionId },
    android: {
      priority: "high",
      notification: { priority: "high", sound: "default" },
    },
    apns: { payload: { aps: { sound: "default" } } },
  };
}

module.exports = {
  buildRideOfferMessage,
  rideLabel,
  validatePushToken,
};
