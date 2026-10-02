"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  callCenterPassengerId,
  maskPhoneNumber,
  normalizeSouthSudanPhone,
  validateCallCenterRideInput,
  validatePlaceSearchQuery,
} = require("../call_center_logic");

test("South Sudan phone variants normalize before dispatch", () => {
  assert.equal(normalizeSouthSudanPhone("092 123 4567"), "+211921234567");
  assert.equal(normalizeSouthSudanPhone("211921234567"), "+211921234567");
  assert.equal(normalizeSouthSudanPhone("00211921234567"), "+211921234567");
  assert.throws(() => normalizeSouthSudanPhone("123"), /valid phone/);
});

test("callers receive stable private passenger identifiers", () => {
  const first = callCenterPassengerId("0921234567");
  const second = callCenterPassengerId("+211 921 234 567");
  assert.equal(first, second);
  assert.match(first, /^call_[a-f0-9]{40}$/);
  assert.equal(maskPhoneNumber("0921234567"), "+2119••••567");
});

test("phone booking validates the same dispatch contract", () => {
  const booking = validateCallCenterRideInput({
    customerName: "  Mary   James ",
    customerPhone: "0921234567",
    customerNote: " Near the blue gate ",
    pickup: { address: "Juba Airport", latitude: 4.872, longitude: 31.601 },
    destination: { address: "Hai Malakal", latitude: 4.84, longitude: 31.58 },
    rideOptionId: "standard",
  });
  assert.equal(booking.customerName, "Mary James");
  assert.equal(booking.customerPhone, "+211921234567");
  assert.equal(booking.paymentMethod, "cash");
  assert.equal(booking.customerNote, "Near the blue gate");
});

test("place queries reject empty and oversized searches", () => {
  assert.equal(validatePlaceSearchQuery("  Juba   Airport "), "Juba Airport");
  assert.throws(() => validatePlaceSearchQuery("J"), /between 2 and/);
  assert.throws(() => validatePlaceSearchQuery("x".repeat(121)), /between 2 and/);
});
