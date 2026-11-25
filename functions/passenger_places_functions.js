"use strict";
const logger = require("firebase-functions/logger");
const { getFirestore } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { HttpsError } = require("firebase-functions/v2/https");
const { onCall } = require("./secure_callable");
const { createPassengerPlaces } = require("./passenger_places_logic");
const placesApiKey = defineSecret("GOOGLE_PLACES_API_KEY");
const places = createPassengerPlaces({ db: getFirestore(), apiKey: () => placesApiKey.value(), HttpsError, logger });
const options = { region: "africa-south1", secrets: [placesApiKey], timeoutSeconds: 20, memory: "256MiB" };
// Keep autocomplete ready for the first keystroke; incurs minimum-instance cost.
exports.passengerSearchPlaces = onCall({ ...options, minInstances: 1 }, places.search);
exports.passengerGetPlace = onCall(options, places.details);



