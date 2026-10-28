"use strict";
const logger = require("firebase-functions/logger");
const { getFirestore } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { createPassengerPlaces } = require("./passenger_places_logic");
const placesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");
const places = createPassengerPlaces({ db: getFirestore(), apiKey: () => placesApiKey.value(), HttpsError, logger });
const options = { region: "africa-south1", secrets: [placesApiKey], timeoutSeconds: 20, memory: "256MiB" };
exports.passengerSearchPlaces = onCall(options, places.search);
exports.passengerGetPlace = onCall(options, places.details);

