"use strict";
const { getFirestore } = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { HttpsError } = require("firebase-functions/v2/https");
const { onCall, requestSecurity } = require("./secure_callable");
const { createPassengerLocations } = require("./passenger_locations_logic");
const locations = createPassengerLocations({ db: getFirestore(), realtimeDb: getDatabase(), HttpsError,
  limit: (...args) => requestSecurity().limit(...args) });
const options = { region: "africa-south1", timeoutSeconds: 15, memory: "256MiB" };
exports.passengerNearbyDrivers = onCall(options, locations.nearby);
exports.passengerAssignedDriverLocation = onCall(options, locations.assigned);
