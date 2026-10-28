"use strict";
const { createHash } = require("node:crypto");
const { validatePlaceSearchQuery, validatePlaceId, parseGooglePlacePredictions, parseGooglePlaceDetails } = require("./call_center_logic");
const { createTtlCache } = require("./runtime_cache");

function validateContext(data, uid) {
  const token = data?.sessionToken;
  if (typeof token !== "string" || !/^[A-Za-z0-9_-]{16,64}$/.test(token)) {
    throw new TypeError("Start a new location search and try again.");
  }
  // Namespace billing sessions by account, without sending a Firebase UID to Google.
  return createHash("sha256").update(`${uid}:${token}`).digest("hex").slice(0, 32);
}

function createPassengerPlaces({ db, apiKey, HttpsError, fetchImpl = fetch, clock = Date.now, logger = console }) {
  const cache = createTtlCache({ ttlMs: 2 * 60 * 1000, maxEntries: 500, clock });
  function requireUid(request) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to search for a location.");
    return request.auth.uid;
  }
  async function authorize(uid) {
    await db.runTransaction(async (tx) => {
      const accountRef = db.collection("account_roles").doc(uid);
      const limitRef = db.collection("passenger_places_limits").doc(uid);
      const [account, limit] = await tx.getAll(accountRef, limitRef);
      if (account.data()?.role !== "passenger" || account.data()?.deletionPending === true) {
        throw new HttpsError("permission-denied", "An active passenger account is required.");
      }
      const windowStartMs = Math.floor(clock() / 60000) * 60000;
      const count = limit.data()?.windowStartMs === windowStartMs ? Number(limit.data()?.count || 0) : 0;
      if (!Number.isInteger(count) || count < 0 || count >= 100) {
        throw new HttpsError("resource-exhausted", "Too many location requests. Wait a moment and try again.");
      }
      tx.set(limitRef, { windowStartMs, count: count + 1 });
    });
  }
  async function google(url, options) {
    const key = apiKey();
    if (typeof key !== "string" || !key.trim()) {
      throw new HttpsError("failed-precondition", "Location search needs server configuration.");
    }
    try {
      const response = await fetchImpl(url, { ...options,
        headers: { ...options.headers, "X-Goog-Api-Key": key },
        signal: AbortSignal.timeout(10000) });
      if (!response.ok) {
        // Log only fixed codes, never provider text, URLs, keys or user queries.
        // This distinguishes API/key/billing setup failures from connectivity.
        let providerStatus = "UNKNOWN";
        let reason = "UNKNOWN";
        try {
          const body = await response.json();
          const allowedStatuses = new Set(["PERMISSION_DENIED", "UNAUTHENTICATED", "INVALID_ARGUMENT", "RESOURCE_EXHAUSTED", "NOT_FOUND", "UNAVAILABLE"]);
          if (allowedStatuses.has(body?.error?.status)) providerStatus = body.error.status;
          const allowedReasons = new Set(["SERVICE_DISABLED", "BILLING_DISABLED", "API_KEY_INVALID", "API_KEY_SERVICE_BLOCKED", "API_KEY_IP_ADDRESS_BLOCKED", "API_KEY_HTTP_REFERRER_BLOCKED", "API_KEY_ANDROID_APP_BLOCKED", "API_KEY_IOS_APP_BLOCKED", "RATE_LIMIT_EXCEEDED", "QUOTA_EXCEEDED"]);
          for (const detail of body?.error?.details || []) {
            if (allowedReasons.has(detail?.reason)) { reason = detail.reason; break; }
          }
        } catch { /* The provider may return a non-JSON error. */ }
        logger.warn("passenger_places_provider_failure", {
          operation: url.includes(":autocomplete") ? "autocomplete" : "details",
          httpStatus: response.status, providerStatus, reason,
        });
        if ([400, 401, 403].includes(response.status)) {
          throw new HttpsError("failed-precondition", "Location search needs server configuration.");
        }
        throw new HttpsError(response.status === 429 ? "resource-exhausted" : "unavailable",
          "Location search is temporarily unavailable. Try again shortly.");
      }
      return await response.json();
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.warn("passenger_places_transport_failure", { operation: url.includes(":autocomplete") ? "autocomplete" : "details" });
      throw new HttpsError("unavailable", "Location search is temporarily unavailable. Try again shortly.");
    }
  }
  function inputError(error) {
    if (error instanceof HttpsError) return error;
    if (error instanceof TypeError || error instanceof RangeError) return new HttpsError("invalid-argument", error.message);
    return new HttpsError("unavailable", "This location could not be loaded. Try again.");
  }
  return {
    async search(request) {
      try {
        const uid = requireUid(request);
        const query = validatePlaceSearchQuery(request.data?.query);
        const { latitude, longitude } = request.data || {};
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
            latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
          throw new RangeError("Enter a valid search location.");
        }
        const sessionToken = validateContext(request.data, uid);
        await authorize(uid);
        const cacheKey = `search:${sessionToken}:${latitude.toFixed(3)}:${longitude.toFixed(3)}:${query.toLowerCase()}`;
        const cached = cache.get(cacheKey);
        if (cached) return { results: cached };
        const payload = await google("https://places.googleapis.com/v1/places:autocomplete", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Goog-FieldMask":
            "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat" },
          body: JSON.stringify({ input: query, sessionToken, languageCode: "en",
            locationBias: { circle: { center: { latitude, longitude }, radius: 50000 } } }),
        });
        return { results: cache.set(cacheKey, parseGooglePlacePredictions(payload)) };
      } catch (error) { throw inputError(error); }
    },
    async details(request) {
      try {
        const uid = requireUid(request);
        const placeId = validatePlaceId(request.data?.placeId);
        const sessionToken = validateContext(request.data, uid);
        await authorize(uid);
        const cacheKey = `details:${sessionToken}:${placeId}`;
        const cached = cache.get(cacheKey);
        if (cached) return cached;
        const payload = await google(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?sessionToken=${sessionToken}`, {
          headers: { "X-Goog-FieldMask": "id,formattedAddress,location" },
        });
        const place = parseGooglePlaceDetails(payload, placeId);
        if (place.latitude < -90 || place.latitude > 90 || place.longitude < -180 || place.longitude > 180) {
          throw new RangeError("This place has no valid map location.");
        }
        return cache.set(cacheKey, place);
      } catch (error) { throw inputError(error); }
    },
  };
}
module.exports = { createPassengerPlaces };

