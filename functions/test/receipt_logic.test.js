"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { buildReceiptNumber } = require("../receipt_logic");

test("receipt number is deterministic and uses the Juba business date", () => {
  const completedAtMillis = Date.parse("2026-09-29T22:30:00.000Z");
  assert.equal(
    buildReceiptNumber({
      rideId: "ride_01JUBAabc12345",
      completedAtMillis,
    }),
    "AR-20260930-BAABC12345",
  );
});

test("receipt number rejects missing ride identity or completion time", () => {
  assert.throws(
    () => buildReceiptNumber({ rideId: "", completedAtMillis: Date.now() }),
    /rideId/,
  );
  assert.throws(
    () => buildReceiptNumber({ rideId: "ride_123", completedAtMillis: 0 }),
    /completedAtMillis/,
  );
});
