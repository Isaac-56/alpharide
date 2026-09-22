"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  hashPhoneNumber,
  inferExistingRole,
  normalizeAccountRole,
  normalizePhoneNumber,
  roleConflictMessage,
} = require("../account_role_logic");

test("account roles normalize to passenger or driver", () => {
  assert.equal(normalizeAccountRole(" Passenger "), "passenger");
  assert.equal(normalizeAccountRole("DRIVER"), "driver");
  assert.throws(() => normalizeAccountRole("admin"), TypeError);
});

test("phone numbers normalize before role lookup", () => {
  assert.equal(normalizePhoneNumber(" +211 922 000 000 "), "+211922000000");
  assert.throws(() => normalizePhoneNumber("0922000000"), TypeError);
  assert.throws(() => normalizePhoneNumber("+211abc"), TypeError);
});

test("phone identity hashes are stable without storing the raw phone", () => {
  const phone = "+211922000000";
  const first = hashPhoneNumber(phone);
  const second = hashPhoneNumber(phone);

  assert.equal(first, second);
  assert.equal(first.length, 64);
  assert.equal(first.includes(phone), false);
});

test("legacy passenger and driver profiles infer the existing role", () => {
  assert.equal(
    inferExistingRole({ legacyPassengerExists: true }),
    "passenger",
  );
  assert.equal(inferExistingRole({ driverExists: true }), "driver");
  assert.equal(inferExistingRole({}), null);
});

test("conflicting passenger and driver records are rejected", () => {
  assert.throws(
    () =>
      inferExistingRole({
        passengerExists: true,
        driverExists: true,
      }),
    RangeError,
  );
});

test("cross-app registration gets a product-specific conflict message", () => {
  assert.match(
    roleConflictMessage("driver", "passenger"),
    /Alpha Plus/,
  );
  assert.match(
    roleConflictMessage("passenger", "driver"),
    /AlphaRide/,
  );
});
