"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ROUTE_PREVIEW_REQUEST_LIMIT,
  ROUTE_PREVIEW_WINDOW_MS,
  advanceRoutePreviewLimit,
  parseGoogleRouteResponse,
  validateRoutePreviewInput,
} = require("../route_logic");

test("route previews accept validated pickup and destination coordinates", () => {
  assert.deepEqual(
    validateRoutePreviewInput({
      origin: { latitude: 4.8517, longitude: 31.5825 },
      destination: { latitude: 4.872, longitude: 31.601 },
    }),
    {
      origin: { latitude: 4.8517, longitude: 31.5825 },
      destination: { latitude: 4.872, longitude: 31.601 },
    },
  );
});

test("route previews reject invalid or identical coordinates", () => {
  assert.throws(
    () => validateRoutePreviewInput({
      origin: { latitude: 91, longitude: 31.5825 },
      destination: { latitude: 4.872, longitude: 31.601 },
    }),
    /outside its valid range/,
  );

  assert.throws(
    () => validateRoutePreviewInput({
      origin: { latitude: 4.8517, longitude: 31.5825 },
      destination: { latitude: 4.8517, longitude: 31.5825 },
    }),
    /cannot be the same/,
  );
});

test("Google route responses expose only trusted preview fields", () => {
  assert.deepEqual(
    parseGoogleRouteResponse(
      {
        routes: [{
          distanceMeters: 4321.4,
          duration: "612.6s",
          polyline: { encodedPolyline: "_p~iF~ps|U_ulLnnqC" },
          ignoredProviderField: "not returned to the app",
        }],
      },
      { includePolyline: true },
    ),
    {
      distanceMeters: 4321,
      durationSeconds: 613,
      encodedPolyline: "_p~iF~ps|U_ulLnnqC",
    },
  );
});

test("Google route responses reject missing or oversized polylines", () => {
  assert.throws(
    () => parseGoogleRouteResponse({
      routes: [{ distanceMeters: 1000, duration: "60s" }],
    }, { includePolyline: true }),
    /invalid route polyline/,
  );

  assert.throws(
    () => parseGoogleRouteResponse({
      routes: [{
        distanceMeters: 1000,
        duration: "60s",
        polyline: { encodedPolyline: "x".repeat(200001) },
      }],
    }, { includePolyline: true }),
    /invalid route polyline/,
  );
});

test("route preview rate limits reset and reject excess requests", () => {
  const now = 100000;
  const fresh = advanceRoutePreviewLimit({
    nowMillis: now,
    windowStartMillis: null,
    requestCount: 0,
  });
  assert.equal(fresh.allowed, true);
  assert.equal(fresh.requestCount, 1);

  const blocked = advanceRoutePreviewLimit({
    nowMillis: now + 5000,
    windowStartMillis: now,
    requestCount: ROUTE_PREVIEW_REQUEST_LIMIT,
  });
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.retryAfterSeconds, 55);

  const reset = advanceRoutePreviewLimit({
    nowMillis: now + ROUTE_PREVIEW_WINDOW_MS,
    windowStartMillis: now,
    requestCount: ROUTE_PREVIEW_REQUEST_LIMIT,
  });
  assert.equal(reset.allowed, true);
  assert.equal(reset.requestCount, 1);
});
