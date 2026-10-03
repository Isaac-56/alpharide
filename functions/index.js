"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const { logger } = require("firebase-functions");
const { defineSecret } = require("firebase-functions/params");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

const {
  ACCEPTANCE_PICKUP_RADIUS_METERS,
  DISPATCH_ALGORITHM_VERSION,
  OFFER_WINDOW_MS,
  PRESENCE_CANDIDATE_SCAN_LIMIT,
  buildDriverPublicSummary,
  presenceAllowsAcceptance,
  presenceIsWithinPickupRadius,
  profileAllowsDispatch,
  selectEligibleDispatchCandidates,
  selectPresenceCandidates,
  validateRideId,
} = require("./dispatch_logic");
const {
  PLATFORM_COMMISSION_BPS,
  commissionBpsFromConfig,
} = require("./accounting_logic");
const {
  CURRENCY_CODE,
  calculateFare,
  isCancellableBeforePickup,
  validateCancellationReason,
  validateCreateRideInput,
  waitingPolicyFor,
} = require("./ride_logic");
const {
  estimatedPlatformFee,
  walletRideEligibility,
} = require("./wallet_logic");
const {
  advanceRoutePreviewLimit,
  buildGoogleRouteRequest,
  parseGoogleRouteResponse,
  validateRoutePreviewInput,
} = require("./route_logic");
const {
  CALL_CENTER_BOOKING_SOURCE,
  callCenterPassengerId,
  maskPhoneNumber,
  parseGooglePlaceDetails,
  parseGooglePlacePredictions,
  validateCallCenterRideInput,
  validatePlaceId,
  validatePlaceSearchQuery,
} = require("./call_center_logic");
const { createTtlCache } = require("./runtime_cache");

initializeApp();

const db = getFirestore();
const realtimeDb = getDatabase();
const googleRoutesApiKey = defineSecret("GOOGLE_ROUTES_API_KEY");

const REGION = "africa-south1";
const ROUTE_PREVIEW_LIMIT_COLLECTION = "route_preview_limits";
const placeSearchCache = createTtlCache({ ttlMs: 5 * 60 * 1000, maxEntries: 250 });
const placeDetailsCache = createTtlCache({ ttlMs: 30 * 60 * 1000, maxEntries: 500 });
const routePreviewCache = createTtlCache({ ttlMs: 3 * 60 * 1000, maxEntries: 150 });
const ACTIVE_RIDE_STATUSES = new Set([
  "requested",
  "offered",
  "accepted",
  "driver_arriving",
  "arrived",
  "in_progress",
]);

function routePreviewCacheKey(pickup, destination) {
  return [
    pickup.latitude,
    pickup.longitude,
    destination.latitude,
    destination.longitude,
  ].map((coordinate) => Number(coordinate).toFixed(5)).join(":");
}

function requireAuthenticatedUser(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "Sign in before using the live ride service.",
    );
  }
  return uid;
}

function requireCustomerServiceAgent(request) {
  const uid = requireAuthenticatedUser(request);
  if (
    request.auth?.token?.customerService !== true &&
    request.auth?.token?.admin !== true
  ) {
    throw new HttpsError(
      "permission-denied",
      "An authorized Alpha customer-service account is required.",
    );
  }
  return uid;
}

function callableError(error, fallbackMessage) {
  if (error instanceof HttpsError) return error;
  if (error instanceof TypeError || error instanceof RangeError) {
    return new HttpsError("invalid-argument", error.message);
  }
  logger.error(fallbackMessage, error);
  return new HttpsError("internal", fallbackMessage);
}

async function computeTrustedRoute(
  pickup,
  destination,
  { includePolyline = false } = {},
) {
  const fieldMask = ["routes.distanceMeters", "routes.duration"];
  if (includePolyline) {
    fieldMask.push("routes.polyline.encodedPolyline");
  }

  let response;
  try {
    response = await fetch(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": googleRoutesApiKey.value(),
          "X-Goog-FieldMask": fieldMask.join(","),
        },
        body: JSON.stringify(
          buildGoogleRouteRequest(pickup, destination, {
            includePolyline,
          }),
        ),
        signal: AbortSignal.timeout(20000),
      },
    );
  } catch (error) {
    logger.error("Google Routes could not be reached", error);
    throw new HttpsError(
      "unavailable",
      "The road route service is temporarily unavailable.",
    );
  }

  if (!response.ok) {
    const body = await response.text();
    logger.error("Google Routes rejected a ride quote", {
      status: response.status,
      body: body.slice(0, 1000),
    });
    throw new HttpsError(
      "unavailable",
      "A road route could not be calculated right now.",
    );
  }

  const payload = await response.json();
  try {
    return parseGoogleRouteResponse(payload, { includePolyline });
  } catch (error) {
    logger.error("Google Routes returned an invalid route", error);
    throw new HttpsError(
      "unavailable",
      "No drivable route was returned for this trip.",
    );
  }
}

async function enforceRoutePreviewLimit(userId) {
  const limitRef = db
    .collection(ROUTE_PREVIEW_LIMIT_COLLECTION)
    .doc(userId);
  const nowMillis = Date.now();
  let limitResult;

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(limitRef);
    const windowStart = snapshot.exists
      ? snapshot.get("windowStart")
      : null;
    limitResult = advanceRoutePreviewLimit({
      nowMillis,
      windowStartMillis: windowStart instanceof Timestamp
        ? windowStart.toMillis()
        : null,
      requestCount: snapshot.exists ? snapshot.get("requestCount") : 0,
    });

    if (!limitResult.allowed) return;

    transaction.set(limitRef, {
      userId,
      windowStart: Timestamp.fromMillis(limitResult.windowStartMillis),
      requestCount: limitResult.requestCount,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  if (!limitResult?.allowed) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many route requests. Please wait a moment and try again.",
      { retryAfterSeconds: limitResult?.retryAfterSeconds ?? 60 },
    );
  }
}

function offerReference(driverId, rideId) {
  return db
    .collection("driver_ride_offers")
    .doc(driverId)
    .collection("offers")
    .doc(rideId);
}

async function markDriverPresenceBusy(driverId, rideId) {
  await realtimeDb.ref(`driver_locations/${driverId}`).update({
    activeRideId: rideId,
    updatedAt: Date.now(),
  });
}

async function clearDriverPresenceBusy(driverId, rideId) {
  const reference = realtimeDb.ref(`driver_locations/${driverId}`);
  await reference.transaction((current) => {
    if (!current || typeof current !== "object") return;
    if (current.activeRideId !== rideId) return;
    const next = { ...current, updatedAt: Date.now() };
    delete next.activeRideId;
    return next;
  });
}

async function markOffers(rideId, driverIds, status) {
  if (!Array.isArray(driverIds) || driverIds.length === 0) return;
  const batch = db.batch();
  const now = FieldValue.serverTimestamp();

  for (const driverId of driverIds) {
    if (typeof driverId !== "string" || !driverId) continue;
    batch.set(
      offerReference(driverId, rideId),
      { status, respondedAt: now },
      { merge: true },
    );
  }
  await batch.commit();
}

async function dispatchRide({
  rideId,
  passengerId,
  pickup,
  destination,
  rideOptionId,
  requiredVehicleType,
  paymentMethod,
  estimatedFare,
  commissionBps,
  bookingSource = "app",
}) {
  const rideRef = db.collection("rides").doc(rideId);
  const presenceSnapshot = await realtimeDb.ref("driver_locations").get();
  const presenceCandidates = selectPresenceCandidates({
    presenceMap: presenceSnapshot.exists() ? presenceSnapshot.val() : null,
    pickup,
    requiredVehicleType,
    limit: PRESENCE_CANDIDATE_SCAN_LIMIT,
  });

  if (presenceCandidates.length === 0) {
    await rideRef.update({
      dispatchState: "no_candidates",
      dispatchCandidateCount: 0,
      dispatchScannedCandidateCount: 0,
      dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
      dispatchAttemptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "requested";
  }

  const verificationResults = await Promise.all(
    presenceCandidates.map(async (candidate) => {
      const [profileSnapshot, activeRideSnapshot, walletSnapshot] =
        await Promise.all([
          db.collection("drivers").doc(candidate.driverId).get(),
          db.collection("active_driver_rides").doc(candidate.driverId).get(),
          db.collection("driver_wallets").doc(candidate.driverId).get(),
        ]);
      return {
        driverId: candidate.driverId,
        profile: profileSnapshot.exists ? profileSnapshot.data() : null,
        busy: activeRideSnapshot.exists,
        wallet: walletSnapshot.exists ? walletSnapshot.data() : null,
      };
    }),
  );
  const profilesByDriverId = Object.fromEntries(
    verificationResults.map((result) => [result.driverId, result.profile]),
  );
  const busyDriverIds = verificationResults
    .filter((result) => result.busy)
    .map((result) => result.driverId);
  const approvedCandidates = selectEligibleDispatchCandidates({
    presenceCandidates,
    profilesByDriverId,
    busyDriverIds,
    requiredVehicleType,
  });
  const walletsByDriverId = Object.fromEntries(
    verificationResults.map((result) => [result.driverId, result.wallet]),
  );
  const verifiedCandidates = approvedCandidates.filter((candidate) =>
    walletRideEligibility({
      wallet: walletsByDriverId[candidate.driverId] ?? {},
      estimatedFare,
      commissionBps,
    }).allowed,
  );

  if (verifiedCandidates.length === 0) {
    await rideRef.update({
      dispatchState: "no_approved_candidates",
      dispatchCandidateCount: 0,
      dispatchScannedCandidateCount: presenceCandidates.length,
      dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
      dispatchAttemptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "requested";
  }

  const driverIds = verifiedCandidates.map((candidate) => candidate.driverId);
  const expiresAt = Timestamp.fromMillis(Date.now() + OFFER_WINDOW_MS);
  const batch = db.batch();

  for (const [candidateIndex, candidate] of verifiedCandidates.entries()) {
    batch.set(offerReference(candidate.driverId, rideId), {
      schemaVersion: 1,
      rideId,
      driverId: candidate.driverId,
      passengerId,
      status: "pending",
      pickup,
      destination,
      rideOptionId,
      requiredVehicleType,
      paymentMethod,
      estimatedFare,
      requiredWalletCredit: estimatedPlatformFee({
        estimatedFare,
        commissionBps,
      }),
      currencyCode: CURRENCY_CODE,
      bookingSource,
      distanceToPickupMeters: candidate.distanceToPickupMeters,
      dispatchRank: candidateIndex + 1,
      dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      respondedAt: null,
    });
  }

  batch.update(rideRef, {
    status: "offered",
    offeredDriverIds: driverIds,
    offerExpiresAt: expiresAt,
    dispatchState: "offers_created",
    dispatchCandidateCount: driverIds.length,
    dispatchScannedCandidateCount: presenceCandidates.length,
    dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
    dispatchAttemptedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return "offered";
}

async function expireOfferedRide(rideRef) {
  let offeredDriverIds = [];
  let expired = false;

  await db.runTransaction(async (transaction) => {
    const rideSnapshot = await transaction.get(rideRef);
    if (!rideSnapshot.exists || rideSnapshot.get("status") !== "offered") {
      return;
    }

    const expiresAt = rideSnapshot.get("offerExpiresAt");
    if (!(expiresAt instanceof Timestamp) || expiresAt.toMillis() > Date.now()) {
      return;
    }

    const passengerId = rideSnapshot.get("passengerId");
    const activePassengerRef = db
      .collection("active_passenger_rides")
      .doc(passengerId);
    const activePassengerSnapshot = await transaction.get(activePassengerRef);
    offeredDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
      ? rideSnapshot.get("offeredDriverIds")
      : [];
    const now = FieldValue.serverTimestamp();

    transaction.update(rideRef, {
      status: "expired",
      offerExpiresAt: null,
      expiredAt: now,
      updatedAt: now,
    });
    if (
      activePassengerSnapshot.exists &&
      activePassengerSnapshot.get("rideId") === rideRef.id
    ) {
      transaction.delete(activePassengerRef);
    }
    expired = true;
  });

  if (expired) {
    await markOffers(rideRef.id, offeredDriverIds, "expired");
  }
}

function timestampMillis(value) {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function safeText(value) {
  return typeof value === "string" ? value : "";
}

function customerServiceRidePayload(rideId, data = {}) {
  const driverSummary = data.driverSummary &&
    typeof data.driverSummary === "object" &&
    !Array.isArray(data.driverSummary)
    ? data.driverSummary
    : {};
  return {
    rideId,
    status: safeText(data.status),
    customerName: safeText(data.customerName),
    customerPhone: safeText(data.customerPhone),
    customerPhoneMasked: data.customerPhone
      ? maskPhoneNumber(data.customerPhone)
      : "",
    customerNote: safeText(data.customerNote),
    pickup: data.pickup ?? null,
    destination: data.destination ?? null,
    rideOptionId: safeText(data.rideOptionId),
    paymentMethod: safeText(data.paymentMethod),
    estimatedFare: Number(data.estimatedFare) || 0,
    finalFare: Number(data.finalFare) || 0,
    currencyCode: safeText(data.currencyCode) || CURRENCY_CODE,
    routeDistanceMeters: Number(data.routeDistanceMeters) || 0,
    routeDurationSeconds: Number(data.routeDurationSeconds) || 0,
    driverId: safeText(data.driverId),
    driverName:
      `${safeText(driverSummary.firstName)} ${safeText(driverSummary.lastName)}`.trim() ||
      safeText(driverSummary.name),
    requestedAtMillis: timestampMillis(data.requestedAt),
    updatedAtMillis: timestampMillis(data.updatedAt),
  };
}

async function fetchGooglePlaces(url, fallbackMessage, options = {}) {
  let response;
  try {
    response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(10000),
    });
  } catch (error) {
    logger.error("Google Places could not be reached", error);
    throw new HttpsError("unavailable", fallbackMessage);
  }
  if (!response.ok) {
    const body = await response.text();
    logger.error("Google Places rejected a call-centre request", {
      status: response.status,
      body: body.slice(0, 1000),
    });
    throw new HttpsError("unavailable", fallbackMessage);
  }
  return response.json();
}

exports.customerServiceSearchPlaces = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const agentId = requireCustomerServiceAgent(request);
      const query = validatePlaceSearchQuery(request.data?.query);
      const cacheKey = query.toLocaleLowerCase("en");
      const cachedResults = placeSearchCache.get(cacheKey);
      if (cachedResults) return { results: cachedResults };
      const searchGooglePlaces = async (input, restrictToSouthSudan) =>
        fetchGooglePlaces(
          "https://places.googleapis.com/v1/places:autocomplete",
          "Location search is temporarily unavailable.",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Goog-Api-Key": googleRoutesApiKey.value(),
              "X-Goog-FieldMask": [
                "suggestions.placePrediction.placeId",
                "suggestions.placePrediction.text",
                "suggestions.placePrediction.structuredFormat",
              ].join(","),
            },
            body: JSON.stringify({
              input,
              ...(restrictToSouthSudan
                ? { includedRegionCodes: ["ss"] }
                : {}),
              languageCode: "en",
              locationBias: {
                circle: {
                  center: { latitude: 4.8594, longitude: 31.5713 },
                  radius: 50000,
                },
              },
            }),
          },
        );

      const [, results] = await Promise.all([
        enforceRoutePreviewLimit(`customer_service_${agentId}`),
        (async () => {
          let predictions = parseGooglePlacePredictions(
            await searchGooglePlaces(query, true),
          );
          if (!predictions.length) {
            predictions = parseGooglePlacePredictions(
              await searchGooglePlaces(`${query}, South Sudan`, false),
            );
          }
          return predictions;
        })(),
      ]);
      placeSearchCache.set(cacheKey, results);
      return { results };
    } catch (error) {
      throw callableError(error, "Unable to search for locations.");
    }
  },
);

exports.customerServiceGetPlace = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    try {
      requireCustomerServiceAgent(request);
      const placeId = validatePlaceId(request.data?.placeId);
      const cachedPlace = placeDetailsCache.get(placeId);
      if (cachedPlace) return cachedPlace;
      const payload = await fetchGooglePlaces(
        `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
        "That location could not be loaded right now.",
        {
          headers: {
            "X-Goog-Api-Key": googleRoutesApiKey.value(),
            "X-Goog-FieldMask": "id,displayName,formattedAddress,location",
          },
        },
      );
      return placeDetailsCache.set(
        placeId,
        parseGooglePlaceDetails(payload, placeId),
      );
    } catch (error) {
      throw callableError(error, "Unable to load the location.");
    }
  },
);

exports.customerServiceQuoteRide = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const agentId = requireCustomerServiceAgent(request);
      const input = validateCreateRideInput({
        pickup: request.data?.pickup,
        destination: request.data?.destination,
        rideOptionId: request.data?.rideOptionId,
        paymentMethod: "cash",
      });
      const cacheKey = routePreviewCacheKey(input.pickup, input.destination);
      let route = routePreviewCache.get(cacheKey);
      if (!route) {
        const [, computedRoute] = await Promise.all([
          enforceRoutePreviewLimit(`customer_service_${agentId}`),
          computeTrustedRoute(
            input.pickup,
            input.destination,
            { includePolyline: true },
          ),
        ]);
        route = routePreviewCache.set(cacheKey, computedRoute);
      }
      return {
        estimatedFare: calculateFare({
          rideOptionId: input.rideOptionId,
          distanceMeters: route.distanceMeters,
        }),
        currencyCode: CURRENCY_CODE,
        routeDistanceMeters: Math.round(route.distanceMeters),
        routeDurationSeconds: Math.round(route.durationSeconds),
        encodedPolyline: route.encodedPolyline,
      };
    } catch (error) {
      throw callableError(error, "Unable to calculate the phone-booking fare.");
    }
  },
);

exports.customerServiceCreateRide = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const agentId = requireCustomerServiceAgent(request);
      const agentEmail = safeText(request.auth?.token?.email);
      const input = validateCallCenterRideInput(request.data);
      const passengerId = callCenterPassengerId(input.customerPhone);
      const [route, accountingConfigSnapshot] = await Promise.all([
        computeTrustedRoute(input.pickup, input.destination),
        db.collection("platform_config").doc("accounting").get(),
      ]);
      const commissionBps = commissionBpsFromConfig(
        accountingConfigSnapshot.exists ? accountingConfigSnapshot.data() : {},
      );
      const estimatedFare = calculateFare({
        rideOptionId: input.rideOptionId,
        distanceMeters: route.distanceMeters,
      });
      const waitingPolicy = waitingPolicyFor(input.rideOptionId);
      const rideRef = db.collection("rides").doc();
      const activeRideRef = db.collection("active_passenger_rides").doc(passengerId);
      const bookingRef = db.collection("call_center_bookings").doc(rideRef.id);
      const auditRef = db.collection("customer_service_audit").doc();

      await db.runTransaction(async (transaction) => {
        const activeSnapshot = await transaction.get(activeRideRef);
        if (activeSnapshot.exists) {
          const activeRideId = activeSnapshot.get("rideId");
          if (typeof activeRideId === "string" && activeRideId) {
            const existingRide = await transaction.get(
              db.collection("rides").doc(activeRideId),
            );
            if (
              existingRide.exists &&
              ACTIVE_RIDE_STATUSES.has(existingRide.get("status"))
            ) {
              throw new HttpsError(
                "already-exists",
                "This phone number already has an active ride.",
                { rideId: activeRideId },
              );
            }
          }
          transaction.delete(activeRideRef);
        }

        const now = FieldValue.serverTimestamp();
        transaction.create(rideRef, {
          schemaVersion: 1,
          bookingSource: CALL_CENTER_BOOKING_SOURCE,
          passengerId,
          customerName: input.customerName,
          customerPhone: input.customerPhone,
          customerNote: input.customerNote,
          createdByStaffId: agentId,
          createdByStaffEmail: agentEmail,
          driverId: null,
          driverSummary: null,
          status: "requested",
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: "cash",
          estimatedFare,
          finalFare: null,
          platformCommissionBps: commissionBps,
          pricingVersion: "juba-distance-wait-v2",
          currencyCode: CURRENCY_CODE,
          routeDistanceMeters: Math.round(route.distanceMeters),
          routeDurationSeconds: Math.round(route.durationSeconds),
          isWaiting: false,
          waitingStartedAt: null,
          waitingSeconds: 0,
          billableWaitingSeconds: 0,
          waitingCharge: 0,
          waitingGraceSeconds: waitingPolicy.graceSeconds,
          waitingRatePerMinute: waitingPolicy.ratePerMinute,
          cancelledBy: null,
          cancellationReason: null,
          offeredDriverIds: [],
          dispatchState: "pending",
          dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
          requestedAt: now,
          updatedAt: now,
          acceptedAt: null,
          arrivedAt: null,
          startedAt: null,
          completedAt: null,
          cancelledAt: null,
        });
        transaction.set(activeRideRef, {
          passengerId,
          rideId: rideRef.id,
          bookingSource: CALL_CENTER_BOOKING_SOURCE,
          createdAt: now,
          updatedAt: now,
        });
        transaction.create(bookingRef, {
          rideId: rideRef.id,
          passengerId,
          customerName: input.customerName,
          customerPhone: input.customerPhone,
          customerPhoneMasked: maskPhoneNumber(input.customerPhone),
          status: "requested",
          createdByStaffId: agentId,
          createdByStaffEmail: agentEmail,
          createdAt: now,
          updatedAt: now,
        });
        transaction.create(auditRef, {
          action: "phone_booking_created",
          actorId: agentId,
          actorEmail: agentEmail,
          rideId: rideRef.id,
          customerPhoneMasked: maskPhoneNumber(input.customerPhone),
          createdAt: now,
        });
      });

      let status = "requested";
      try {
        status = await dispatchRide({
          rideId: rideRef.id,
          passengerId,
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: "cash",
          estimatedFare,
          commissionBps,
          bookingSource: CALL_CENTER_BOOKING_SOURCE,
        });
      } catch (dispatchError) {
        logger.error("Call-centre ride dispatch failed", {
          rideId: rideRef.id,
          error: dispatchError,
        });
        await rideRef.update({
          dispatchState: "error",
          dispatchAttemptedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }).catch(() => {});
      }
      await bookingRef.set(
        { status, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );

      return {
        rideId: rideRef.id,
        status,
        estimatedFare,
        currencyCode: CURRENCY_CODE,
        routeDistanceMeters: Math.round(route.distanceMeters),
        routeDurationSeconds: Math.round(route.durationSeconds),
      };
    } catch (error) {
      throw callableError(error, "Unable to create the phone booking.");
    }
  },
);

exports.customerServiceListBookings = onCall(
  { region: REGION, timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    try {
      requireCustomerServiceAgent(request);
      const rawLimit = request.data?.limit;
      const limit = rawLimit == null
        ? 50
        : Math.min(Math.max(Number(rawLimit) || 1, 1), 100);
      const bookingSnapshot = await db
        .collection("call_center_bookings")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();
      const rideRefs = bookingSnapshot.docs.map((document) =>
        db.collection("rides").doc(document.id));
      const rides = rideRefs.length ? await db.getAll(...rideRefs) : [];
      return {
        bookings: rides
          .filter((document) => document.exists)
          .map((document) => customerServiceRidePayload(
            document.id,
            document.data(),
          )),
      };
    } catch (error) {
      throw callableError(error, "Unable to load phone bookings.");
    }
  },
);

exports.customerServiceCancelRide = onCall(
  { region: REGION, timeoutSeconds: 20, memory: "256MiB" },
  async (request) => {
    try {
      const agentId = requireCustomerServiceAgent(request);
      const agentEmail = safeText(request.auth?.token?.email);
      const rideId = validateRideId(request.data?.rideId);
      const cancellationReason = validateCancellationReason(
        request.data?.reason || "Cancelled by customer service",
      );
      const rideRef = db.collection("rides").doc(rideId);
      const bookingRef = db.collection("call_center_bookings").doc(rideId);
      const auditRef = db.collection("customer_service_audit").doc();
      let offeredDriverIds = [];
      let assignedDriverId = null;

      await db.runTransaction(async (transaction) => {
        const rideSnapshot = await transaction.get(rideRef);
        if (!rideSnapshot.exists) {
          throw new HttpsError("not-found", "The booking no longer exists.");
        }
        if (rideSnapshot.get("bookingSource") !== CALL_CENTER_BOOKING_SOURCE) {
          throw new HttpsError(
            "permission-denied",
            "Customer service can only cancel phone bookings.",
          );
        }
        const passengerId = rideSnapshot.get("passengerId");
        const activePassengerRef = db
          .collection("active_passenger_rides")
          .doc(passengerId);
        const activePassengerSnapshot = await transaction.get(activePassengerRef);
        assignedDriverId = safeText(rideSnapshot.get("driverId")) || null;
        const activeDriverRef = assignedDriverId
          ? db.collection("active_driver_rides").doc(assignedDriverId)
          : null;
        const activeDriverSnapshot = activeDriverRef
          ? await transaction.get(activeDriverRef)
          : null;
        offeredDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const status = rideSnapshot.get("status");
        if (status !== "cancelled" && !isCancellableBeforePickup(status)) {
          throw new HttpsError(
            "failed-precondition",
            "This trip has started and can no longer be cancelled here.",
          );
        }
        const now = FieldValue.serverTimestamp();
        if (status !== "cancelled") {
          transaction.update(rideRef, {
            status: "cancelled",
            offerExpiresAt: null,
            isWaiting: false,
            waitingStartedAt: null,
            cancelledBy: "customer_service",
            cancellationReason,
            cancelledAt: now,
            updatedAt: now,
          });
        }
        transaction.set(bookingRef, { status: "cancelled", updatedAt: now }, { merge: true });
        if (
          activePassengerSnapshot.exists &&
          activePassengerSnapshot.get("rideId") === rideId
        ) transaction.delete(activePassengerRef);
        if (
          activeDriverRef &&
          activeDriverSnapshot?.exists &&
          activeDriverSnapshot.get("rideId") === rideId
        ) transaction.delete(activeDriverRef);
        transaction.create(auditRef, {
          action: "phone_booking_cancelled",
          actorId: agentId,
          actorEmail: agentEmail,
          rideId,
          reason: cancellationReason,
          createdAt: now,
        });
      });

      if (assignedDriverId && !offeredDriverIds.includes(assignedDriverId)) {
        offeredDriverIds.push(assignedDriverId);
      }
      if (assignedDriverId) {
        await clearDriverPresenceBusy(assignedDriverId, rideId).catch(() => {});
      }
      await markOffers(rideId, offeredDriverIds, "cancelled").catch(() => {});
      return { rideId, status: "cancelled" };
    } catch (error) {
      throw callableError(error, "Unable to cancel the phone booking.");
    }
  },
);

exports.calculateRoute = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const userId = requireAuthenticatedUser(request);
      const input = validateRoutePreviewInput(request.data);
      await enforceRoutePreviewLimit(userId);
      const route = await computeTrustedRoute(
        input.origin,
        input.destination,
        { includePolyline: true },
      );

      return {
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
        encodedPolyline: route.encodedPolyline,
      };
    } catch (error) {
      throw callableError(error, "Unable to calculate the road route.");
    }
  },
);

exports.createRide = onCall(
  {
    region: REGION,
    secrets: [googleRoutesApiKey],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    try {
      const passengerId = requireAuthenticatedUser(request);
      const input = validateCreateRideInput(request.data);
      const customerPhone = typeof request.auth?.token?.phone_number === "string"
        ? request.auth.token.phone_number.trim()
        : "";
      const [route, accountingConfigSnapshot] = await Promise.all([
        computeTrustedRoute(input.pickup, input.destination),
        db.collection("platform_config").doc("accounting").get(),
      ]);
      const commissionBps = commissionBpsFromConfig(
        accountingConfigSnapshot.exists ? accountingConfigSnapshot.data() : {},
      );
      const estimatedFare = calculateFare({
        rideOptionId: input.rideOptionId,
        distanceMeters: route.distanceMeters,
      });
      const waitingPolicy = waitingPolicyFor(input.rideOptionId);

      const rideRef = db.collection("rides").doc();
      const activeRideRef = db
        .collection("active_passenger_rides")
        .doc(passengerId);

      await db.runTransaction(async (transaction) => {
        const activeSnapshot = await transaction.get(activeRideRef);
        if (activeSnapshot.exists) {
          const activeRideId = activeSnapshot.get("rideId");
          if (typeof activeRideId === "string" && activeRideId) {
            const existingRideRef = db.collection("rides").doc(activeRideId);
            const existingRide = await transaction.get(existingRideRef);
            if (
              existingRide.exists &&
              ACTIVE_RIDE_STATUSES.has(existingRide.get("status"))
            ) {
              throw new HttpsError(
                "already-exists",
                "You already have an active ride.",
                { rideId: activeRideId },
              );
            }
          }
          transaction.delete(activeRideRef);
        }

        const now = FieldValue.serverTimestamp();
        transaction.create(rideRef, {
          schemaVersion: 1,
          passengerId,
          customerPhone,
          driverId: null,
          driverSummary: null,
          status: "requested",
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: input.paymentMethod,
          estimatedFare,
          finalFare: null,
          platformCommissionBps: commissionBps,
          pricingVersion: "juba-distance-wait-v2",
          currencyCode: CURRENCY_CODE,
          routeDistanceMeters: Math.round(route.distanceMeters),
          routeDurationSeconds: Math.round(route.durationSeconds),
          isWaiting: false,
          waitingStartedAt: null,
          waitingSeconds: 0,
          billableWaitingSeconds: 0,
          waitingCharge: 0,
          waitingGraceSeconds: waitingPolicy.graceSeconds,
          waitingRatePerMinute: waitingPolicy.ratePerMinute,
          cancelledBy: null,
          cancellationReason: null,
          offeredDriverIds: [],
          dispatchState: "pending",
          dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
          requestedAt: now,
          updatedAt: now,
          acceptedAt: null,
          arrivedAt: null,
          startedAt: null,
          completedAt: null,
          cancelledAt: null,
        });
        transaction.set(activeRideRef, {
          passengerId,
          rideId: rideRef.id,
          createdAt: now,
          updatedAt: now,
        });
      });

      let status = "requested";
      try {
        status = await dispatchRide({
          rideId: rideRef.id,
          passengerId,
          pickup: input.pickup,
          destination: input.destination,
          rideOptionId: input.rideOptionId,
          requiredVehicleType: input.rideOptionId,
          paymentMethod: input.paymentMethod,
          estimatedFare,
          commissionBps,
        });
      } catch (dispatchError) {
        logger.error("Initial ride dispatch failed", {
          rideId: rideRef.id,
          error: dispatchError,
        });
        await rideRef
          .update({
            dispatchState: "error",
            dispatchAttemptedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          })
          .catch(() => {});
      }

      return {
        rideId: rideRef.id,
        status,
        estimatedFare,
        currencyCode: CURRENCY_CODE,
        routeDistanceMeters: Math.round(route.distanceMeters),
        routeDurationSeconds: Math.round(route.durationSeconds),
      };
    } catch (error) {
      throw callableError(error, "Unable to create the ride.");
    }
  },
);

exports.cancelRide = onCall(
  { region: REGION, timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    try {
      const passengerId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const cancellationReason = validateCancellationReason(
        request.data?.reason,
      );
      const rideRef = db.collection("rides").doc(rideId);
      const activeRideRef = db
        .collection("active_passenger_rides")
        .doc(passengerId);
      let offeredDriverIds = [];
      let assignedDriverId = null;

      await db.runTransaction(async (transaction) => {
        const rideSnapshot = await transaction.get(rideRef);
        const activeSnapshot = await transaction.get(activeRideRef);
        if (!rideSnapshot.exists) {
          throw new HttpsError("not-found", "The ride no longer exists.");
        }
        if (rideSnapshot.get("passengerId") !== passengerId) {
          throw new HttpsError(
            "permission-denied",
            "This ride belongs to another passenger.",
          );
        }

        offeredDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const rawDriverId = rideSnapshot.get("driverId");
        assignedDriverId =
          typeof rawDriverId === "string" && rawDriverId.trim()
            ? rawDriverId.trim()
            : null;
        const activeDriverRef = assignedDriverId
          ? db.collection("active_driver_rides").doc(assignedDriverId)
          : null;
        const activeDriverSnapshot = activeDriverRef
          ? await transaction.get(activeDriverRef)
          : null;
        const status = rideSnapshot.get("status");
        if (status === "cancelled") {
          if (
            activeSnapshot.exists &&
            activeSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activeRideRef);
          }
          if (
            activeDriverRef &&
            activeDriverSnapshot?.exists &&
            activeDriverSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activeDriverRef);
          }
          return;
        }
        if (!isCancellableBeforePickup(status)) {
          throw new HttpsError(
            "failed-precondition",
            "This ride can no longer be cancelled from the passenger app.",
          );
        }

        transaction.update(rideRef, {
          status: "cancelled",
          offerExpiresAt: null,
          isWaiting: false,
          waitingStartedAt: null,
          cancelledBy: "passenger",
          cancellationReason,
          cancelledAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        if (
          activeSnapshot.exists &&
          activeSnapshot.get("rideId") === rideId
        ) {
          transaction.delete(activeRideRef);
        }
        if (
          activeDriverRef &&
          activeDriverSnapshot?.exists &&
          activeDriverSnapshot.get("rideId") === rideId
        ) {
          transaction.delete(activeDriverRef);
        }
      });

      if (
        assignedDriverId &&
        !offeredDriverIds.includes(assignedDriverId)
      ) {
        offeredDriverIds.push(assignedDriverId);
      }

      const cleanupTasks = [
        markOffers(rideId, offeredDriverIds, "cancelled").catch(
          (cleanupError) => {
            logger.warn("Could not close cancelled ride offers", {
              rideId,
              error: cleanupError,
            });
          },
        ),
      ];
      if (assignedDriverId) {
        cleanupTasks.push(
          clearDriverPresenceBusy(assignedDriverId, rideId).catch(
            (cleanupError) => {
              logger.warn("Could not clear cancelled driver presence", {
                rideId,
                driverId: assignedDriverId,
                error: cleanupError,
              });
            },
          ),
        );
      }
      await Promise.all(cleanupTasks);
      return { rideId, status: "cancelled" };
    } catch (error) {
      throw callableError(error, "Unable to cancel the ride.");
    }
  },
);

exports.acceptRideOffer = onCall(
  { region: REGION, timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    try {
      const driverId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const rideRef = db.collection("rides").doc(rideId);
      const offerRef = offerReference(driverId, rideId);
      const profileRef = db.collection("drivers").doc(driverId);
      const activeDriverRef = db
        .collection("active_driver_rides")
        .doc(driverId);
      const walletRef = db.collection("driver_wallets").doc(driverId);

      const preOffer = await offerRef.get();
      if (!preOffer.exists || preOffer.get("status") !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          "This ride offer is no longer active.",
        );
      }
      const presenceSnapshot = await realtimeDb
        .ref(`driver_locations/${driverId}`)
        .get();
      if (
        !presenceAllowsAcceptance({
          presence: presenceSnapshot.exists() ? presenceSnapshot.val() : null,
          driverId,
          requiredVehicleType: preOffer.get("requiredVehicleType"),
        }) ||
        !presenceIsWithinPickupRadius({
          presence: presenceSnapshot.exists() ? presenceSnapshot.val() : null,
          pickup: preOffer.get("pickup"),
          radiusMeters: ACCEPTANCE_PICKUP_RADIUS_METERS,
        })
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Go online with your approved vehicle before accepting this ride.",
        );
      }

      let competingDriverIds = [];
      await db.runTransaction(async (transaction) => {
        const offerSnapshot = await transaction.get(offerRef);
        const rideSnapshot = await transaction.get(rideRef);
        const profileSnapshot = await transaction.get(profileRef);
        const activeDriverSnapshot = await transaction.get(activeDriverRef);
        const walletSnapshot = await transaction.get(walletRef);

        if (!offerSnapshot.exists || !rideSnapshot.exists) {
          throw new HttpsError(
            "not-found",
            "This ride offer is no longer available.",
          );
        }
        if (
          rideSnapshot.get("status") === "accepted" &&
          rideSnapshot.get("driverId") === driverId
        ) {
          return;
        }
        if (offerSnapshot.get("status") !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "This offer is no longer active.",
          );
        }

        const expiresAt = offerSnapshot.get("expiresAt");
        if (
          !(expiresAt instanceof Timestamp) ||
          expiresAt.toMillis() <= Date.now()
        ) {
          throw new HttpsError(
            "failed-precondition",
            "This ride offer has expired.",
          );
        }
        if (
          rideSnapshot.get("status") !== "offered" ||
          rideSnapshot.get("driverId") != null
        ) {
          throw new HttpsError(
            "already-exists",
            "Another driver already accepted this ride.",
          );
        }

        const requiredVehicleType = rideSnapshot.get("requiredVehicleType");
        if (
          !profileSnapshot.exists ||
          !profileAllowsDispatch(profileSnapshot.data(), requiredVehicleType)
        ) {
          throw new HttpsError(
            "permission-denied",
            "Your approved vehicle is not eligible for this ride.",
          );
        }
        if (
          activeDriverSnapshot.exists &&
          activeDriverSnapshot.get("rideId") !== rideId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Finish your active ride before accepting another request.",
          );
        }

        const walletEligibility = walletRideEligibility({
          wallet: walletSnapshot.exists ? walletSnapshot.data() : {},
          estimatedFare: rideSnapshot.get("estimatedFare"),
          commissionBps:
            rideSnapshot.get("platformCommissionBps") ??
            PLATFORM_COMMISSION_BPS,
        });
        if (!walletEligibility.allowed) {
          const message = walletEligibility.reason === "wallet_suspended"
            ? "Your driver wallet is suspended. Visit the Alpha office for help."
            : walletEligibility.reason === "wallet_empty"
              ? "Recharge your driver wallet at the Alpha office before accepting rides."
              : "Your wallet does not cover this ride's estimated Alpha fee. Recharge before accepting.";
          throw new HttpsError(
            "failed-precondition",
            message,
            {
              reason: walletEligibility.reason,
              balance: walletEligibility.balance,
              requiredCredit: walletEligibility.requiredCredit,
              currencyCode: walletEligibility.currencyCode,
            },
          );
        }

        competingDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const driverSummary = buildDriverPublicSummary(profileSnapshot.data());
        const now = FieldValue.serverTimestamp();
        transaction.update(rideRef, {
          status: "accepted",
          driverId,
          driverSummary,
          offerExpiresAt: null,
          acceptedAt: now,
          updatedAt: now,
        });
        transaction.update(offerRef, {
          status: "accepted",
          respondedAt: now,
        });
        transaction.set(activeDriverRef, {
          driverId,
          rideId,
          createdAt: now,
          updatedAt: now,
        });
      });

      await markDriverPresenceBusy(driverId, rideId);
      await markOffers(
        rideId,
        competingDriverIds.filter((candidateId) => candidateId !== driverId),
        "expired",
      ).catch((cleanupError) => {
        logger.warn("Could not expire competing ride offers", {
          rideId,
          driverId,
          error: cleanupError,
        });
      });

      return { rideId, status: "accepted", driverId };
    } catch (error) {
      throw callableError(error, "Unable to accept the ride offer.");
    }
  },
);

exports.rejectRideOffer = onCall(
  { region: REGION, timeoutSeconds: 15, memory: "256MiB" },
  async (request) => {
    try {
      const driverId = requireAuthenticatedUser(request);
      const rideId = validateRideId(request.data?.rideId);
      const rideRef = db.collection("rides").doc(rideId);
      const offerRef = offerReference(driverId, rideId);
      let rideExpired = false;
      let allDriverIds = [];

      await db.runTransaction(async (transaction) => {
        const offerSnapshot = await transaction.get(offerRef);
        const rideSnapshot = await transaction.get(rideRef);
        if (!offerSnapshot.exists) {
          throw new HttpsError(
            "not-found",
            "This ride offer is no longer available.",
          );
        }

        const currentOfferStatus = offerSnapshot.get("status");
        if (
          currentOfferStatus === "rejected" ||
          currentOfferStatus === "expired"
        ) {
          return;
        }
        if (currentOfferStatus !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "This offer is no longer active.",
          );
        }
        if (!rideSnapshot.exists || rideSnapshot.get("status") !== "offered") {
          transaction.update(offerRef, {
            status: "expired",
            respondedAt: FieldValue.serverTimestamp(),
          });
          return;
        }

        allDriverIds = Array.isArray(rideSnapshot.get("offeredDriverIds"))
          ? rideSnapshot.get("offeredDriverIds")
          : [];
        const otherRefs = allDriverIds
          .filter((candidateId) => candidateId !== driverId)
          .map((candidateId) => offerReference(candidateId, rideId));
        const otherSnapshots = [];
        for (const otherRef of otherRefs) {
          otherSnapshots.push(await transaction.get(otherRef));
        }
        const nowMs = Date.now();
        const anotherOfferActive = otherSnapshots.some((snapshot) => {
          if (!snapshot.exists || snapshot.get("status") !== "pending") {
            return false;
          }
          const expiresAt = snapshot.get("expiresAt");
          return expiresAt instanceof Timestamp && expiresAt.toMillis() > nowMs;
        });

        let activePassengerRef = null;
        let activePassengerSnapshot = null;
        if (!anotherOfferActive) {
          activePassengerRef = db
            .collection("active_passenger_rides")
            .doc(rideSnapshot.get("passengerId"));
          activePassengerSnapshot = await transaction.get(activePassengerRef);
        }

        const now = FieldValue.serverTimestamp();
        transaction.update(offerRef, {
          status: "rejected",
          respondedAt: now,
        });

        if (!anotherOfferActive) {
          transaction.update(rideRef, {
            status: "expired",
            offerExpiresAt: null,
            expiredAt: now,
            updatedAt: now,
          });
          if (
            activePassengerRef != null &&
            activePassengerSnapshot.exists &&
            activePassengerSnapshot.get("rideId") === rideId
          ) {
            transaction.delete(activePassengerRef);
          }
          rideExpired = true;
        }
      });

      if (rideExpired) {
        await markOffers(rideId, allDriverIds, "expired").catch(() => {});
      }
      return {
        rideId,
        status: rideExpired ? "expired" : "rejected",
        driverId,
      };
    } catch (error) {
      throw callableError(error, "Unable to reject the ride offer.");
    }
  },
);

exports.expireRideOffers = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 1 minutes",
    timeZone: "UTC",
    memory: "256MiB",
  },
  async () => {
    const snapshot = await db
      .collection("rides")
      .where("offerExpiresAt", "<=", Timestamp.now())
      .limit(50)
      .get();

    for (const rideSnapshot of snapshot.docs) {
      try {
        await expireOfferedRide(rideSnapshot.ref);
      } catch (error) {
        logger.error("Could not expire a ride offer window", {
          rideId: rideSnapshot.id,
          error,
        });
      }
    }
  },
);
