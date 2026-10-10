"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  ACCOUNTING_VERSION,
  MAX_PLATFORM_COMMISSION_BPS,
  PLATFORM_COMMISSION_BPS,
  calculateCompletedRideAccounting,
  commissionBpsFromConfig,
  normalizeCommissionBps,
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

test("configured commission is normalized and frozen in basis points", () => {
  assert.equal(commissionBpsFromConfig({ commissionBps: 1250 }), 1250);
  assert.equal(commissionBpsFromConfig({}), PLATFORM_COMMISSION_BPS);
  assert.equal(normalizeCommissionBps(0), 0);
  assert.throws(
    () => normalizeCommissionBps(MAX_PLATFORM_COMMISSION_BPS + 1),
    /between 0 and 5000/,
  );

  const accounting = calculateCompletedRideAccounting({
    grossFare: 100000,
    paymentMethod: "cash",
    commissionBps: 1250,
  });
  assert.equal(accounting.platformFee, 12500);
  assert.equal(accounting.driverNetFare, 87500);
});

test("commission settings are independent by ride category", () => {
  const config = {
    commissionBps: 1000,
    commissionByRideOption: { boda: 500, premium: 1750 },
  };
  assert.equal(commissionBpsFromConfig(config, "boda"), 500);
  assert.equal(commissionBpsFromConfig(config, "premium"), 1750);
  assert.equal(commissionBpsFromConfig(config, "standard"), 1000);
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
