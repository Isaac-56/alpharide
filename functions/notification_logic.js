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
  dispatchRound,
}) {
  const round = Number.isInteger(dispatchRound) && dispatchRound > 0 ? dispatchRound : 0;
  const eventId = `ride_offer:${rideId}${round ? `:${round}` : ""}`;
  return {
    token: validatePushToken(token),
    notification: {
      title: `New ${rideLabel(rideOptionId)} ride request`,
      body: `${pickupAddress} · ${estimatedFare} ${currencyCode}`,
    },
    data: { type: "ride_offer", rideId, rideOptionId, eventId, dispatchRound: String(round) },
    android: {
      priority: "high",
      ttl: 30000,
      notification: { priority: "high", sound: "alpha_luxe", channelId: "alpha_ride_alerts_luxe_v2", tag: eventId },
    },
    apns: { payload: { aps: { sound: "alpha_luxe.wav" } } },
  };
}

function buildUpdateMessage({ token, eventId, title, body, type = "news" }) {
  const urgent = type === "ride_update";
  return {
    token: validatePushToken(token),
    notification: { title: String(title).slice(0, 120), body: String(body).slice(0, 500) },
    data: { type, eventId },
    android: { priority: urgent ? "high" : "normal", notification: {
      channelId: urgent ? "alpha_ride_alerts_luxe_v2" : "alpha_updates_luxe_v2",
      sound: "alpha_luxe", tag: eventId,
    } },
    apns: { payload: { aps: { sound: "alpha_luxe.wav" } } },
  };
}

function passengerRideUpdate(before, after) {
  if (!before || !after || before.status === after.status) return null;
  const updates = {
    accepted: ["Driver accepted your ride", "Your driver is preparing to pick you up."],
    arrived: ["Your driver has arrived", "Meet your driver at the pickup location."],
    in_progress: ["Your trip has started", "Follow your trip in Alpha Ride."],
    completed: ["Your trip is complete", "Open Alpha Ride to view your final fare."],
    cancelled: ["Your ride was cancelled", "Open Alpha Ride for the latest ride status."],
  };
  const update = updates[after.status];
  return update ? { title: update[0], body: update[1], type: "ride_update" } : null;
}

module.exports = {
  buildUpdateMessage,
  passengerRideUpdate,
  buildRideOfferMessage,
  rideLabel,
  validatePushToken,
};

