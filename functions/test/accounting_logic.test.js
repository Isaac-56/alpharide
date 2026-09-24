"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCOUNTING_VERSION,
  PLATFORM_COMMISSION_BPS,
  calculateCompletedRideAccounting,
} = require("../accounting_logic");

test("cash completion gives Alpha 10 percent and records a wallet deduction", () => {
  assert.deepEqual(
    calculateCompletedRideAccounting({
      grossFare: 21500,
      paymentMethod: "cash",
    }),
    {
      accountingVersion: ACCOUNTING_VERSION,
      grossFare: 21500,
      platformCommissionBps: PLATFORM_COMMISSION_BPS,
      platformFee: 2150,
      driverNetFare: 19350,
      cashCollectedByDriver: 21500,
      settlementStatus: "wallet_deducted",
    },
  );
});

test("commission uses integer SSP rounding", () => {
  const accounting = calculateCompletedRideAccounting({
    grossFare: 10001,
    paymentMethod: "cash",
  });

  assert.equal(accounting.platformFee, 1000);
  assert.equal(accounting.driverNetFare, 9001);
});

test("launch accounting rejects invalid fares and unimplemented payments", () => {
  assert.throws(
    () =>
      calculateCompletedRideAccounting({
        grossFare: 0,
        paymentMethod: "cash",
      }),
    /positive integer/,
  );
  assert.throws(
    () =>
      calculateCompletedRideAccounting({
        grossFare: 10000,
        paymentMethod: "wallet",
      }),
    /only cash ride accounting/,
  );
});
