"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { resolveTrackedRideProgress } = require("../lifecycle_logic");
test("a rejected teleport cannot become the trusted baseline for the next point", () => {
  const previousPoint = { latitude: 4.85, longitude: 31.58, accuracy: 5 };
  const result = resolveTrackedRideProgress({ previousPoint, previousAtMillis: 1000, nowMillis: 1100,
    nextPoint: { ...previousPoint, latitude: 5.85 }, trackedDistanceMeters: 120 });
  assert.equal(result.trackedDistanceMeters, 120); assert.deepEqual(result.point, previousPoint);
});
test("same-timestamp movement cannot repeatedly exploit a minimum-distance allowance", () => {
  const previousPoint = { latitude: 4.85, longitude: 31.58, accuracy: 5 };
  const result = resolveTrackedRideProgress({ previousPoint, previousAtMillis: 1000, nowMillis: 1000,
    nextPoint: { ...previousPoint, latitude: 4.851 }, trackedDistanceMeters: 120 });
  assert.equal(result.trackedDistanceMeters, 120); assert.deepEqual(result.point, previousPoint);
});
