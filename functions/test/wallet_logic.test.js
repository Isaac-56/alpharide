"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_LOW_BALANCE_THRESHOLD,
  applyWalletCredit,
  applyWalletDebit,
  estimatedPlatformFee,
  normalizeTopUpAmount,
  walletRideEligibility,
  walletState,
} = require("../wallet_logic");

test("new driver wallet starts empty and cannot work", () => {
  assert.deepEqual(walletState(), {
    schemaVersion: 1,
    currencyCode: "SSP",
    balance: 0,
    lowBalanceThreshold: DEFAULT_LOW_BALANCE_THRESHOLD,
    status: "active",
    isLowBalance: true,
    canGoOnline: false,
  });
});

test("positive prepaid balance enables online work", () => {
  const state = walletState({ balance: 25000 });
  assert.equal(state.canGoOnline, true);
  assert.equal(state.isLowBalance, false);
});

test("low credit warns while still allowing online work", () => {
  const state = walletState({ balance: 5000 });
  assert.equal(state.canGoOnline, true);
  assert.equal(state.isLowBalance, true);
});

test("estimated ten percent fee must be covered before acceptance", () => {
  assert.equal(
    estimatedPlatformFee({ estimatedFare: 68000, commissionBps: 1000 }),
    6800,
  );
  assert.equal(
    walletRideEligibility({
      wallet: { balance: 6800 },
      estimatedFare: 68000,
      commissionBps: 1000,
    }).allowed,
    true,
  );
  assert.deepEqual(
    walletRideEligibility({
      wallet: { balance: 6799 },
      estimatedFare: 68000,
      commissionBps: 1000,
    }),
    {
      schemaVersion: 1,
      currencyCode: "SSP",
      balance: 6799,
      lowBalanceThreshold: DEFAULT_LOW_BALANCE_THRESHOLD,
      status: "active",
      isLowBalance: true,
      canGoOnline: true,
      requiredCredit: 6800,
      allowed: false,
      reason: "insufficient_credit",
    },
  );
});

test("suspended wallets cannot work even with credit", () => {
  const eligibility = walletRideEligibility({
    wallet: { balance: 50000, status: "suspended" },
    estimatedFare: 20000,
    commissionBps: 1000,
  });
  assert.equal(eligibility.allowed, false);
  assert.equal(eligibility.reason, "wallet_suspended");
});

test("credits and ride fees preserve an auditable integer balance", () => {
  const credited = applyWalletCredit({ wallet: { balance: 1000 }, amount: 9000 });
  const debited = applyWalletDebit({ wallet: credited, amount: 2500 });
  assert.equal(credited.balance, 10000);
  assert.equal(debited.balance, 7500);
});

test("top ups reject zero, fractions and excessive values", () => {
  assert.throws(() => normalizeTopUpAmount(0), /positive integer/);
  assert.throws(() => normalizeTopUpAmount(10.5), /integer/);
  assert.throws(() => normalizeTopUpAmount(1000000001), /maximum/);
});
