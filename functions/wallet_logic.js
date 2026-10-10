"use strict";

const WALLET_SCHEMA_VERSION = 1;
const DEFAULT_LOW_BALANCE_THRESHOLD = 20000;
const WALLET_STATUS_ACTIVE = "active";
const WALLET_STATUS_SUSPENDED = "suspended";
const MAX_TOP_UP_AMOUNT = 1000000000;

function integer(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new RangeError(`${fieldName} must be an integer`);
  }
  return value;
}

function positiveInteger(value, fieldName) {
  const normalized = integer(value, fieldName);
  if (normalized <= 0) {
    throw new RangeError(`${fieldName} must be a positive integer`);
  }
  return normalized;
}

function normalizeWalletStatus(value) {
  const normalized =
    typeof value === "string" ? value.trim().toLowerCase() : "";
  if (!normalized || normalized === WALLET_STATUS_ACTIVE) {
    return WALLET_STATUS_ACTIVE;
  }
  if (normalized === WALLET_STATUS_SUSPENDED) {
    return WALLET_STATUS_SUSPENDED;
  }
  throw new RangeError("wallet status must be active or suspended");
}

function walletState(data = {}) {
  const rawBalance = data?.balance ?? 0;
  const rawThreshold =
    data?.lowBalanceThreshold ?? DEFAULT_LOW_BALANCE_THRESHOLD;
  const balance = integer(rawBalance, "wallet balance");
  const lowBalanceThreshold = positiveInteger(
    rawThreshold,
    "lowBalanceThreshold",
  );
  const status = normalizeWalletStatus(data?.status);
  const isLowBalance = balance < lowBalanceThreshold;
  const canGoOnline = status === WALLET_STATUS_ACTIVE && balance > 0;

  return Object.freeze({
    schemaVersion: WALLET_SCHEMA_VERSION,
    currencyCode: "SSP",
    balance,
    lowBalanceThreshold,
    status,
    isLowBalance,
    canGoOnline,
  });
}

function estimatedPlatformFee({
  estimatedFare,
  commissionBps,
}) {
  const fare = positiveInteger(estimatedFare, "estimatedFare");
  const basisPoints = positiveInteger(commissionBps, "commissionBps");
  if (basisPoints >= 10000) {
    throw new RangeError("commissionBps must be less than 10000");
  }
  return Math.round((fare * basisPoints) / 10000);
}

function walletRideEligibility({
  wallet,
  estimatedFare,
  commissionBps,
}) {
  const state = walletState(wallet);
  const requiredCredit = estimatedPlatformFee({
    estimatedFare,
    commissionBps,
  });
  const allowed =
    state.canGoOnline && state.balance >= requiredCredit;

  let reason = null;
  if (state.status === WALLET_STATUS_SUSPENDED) {
    reason = "wallet_suspended";
  } else if (state.balance <= 0) {
    reason = "wallet_empty";
  } else if (state.balance < requiredCredit) {
    reason = "insufficient_credit";
  }

  return Object.freeze({
    ...state,
    requiredCredit,
    allowed,
    reason,
  });
}

function normalizeTopUpAmount(value) {
  const amount = positiveInteger(value, "top-up amount");
  if (amount > MAX_TOP_UP_AMOUNT) {
    throw new RangeError("top-up amount is above the allowed maximum");
  }
  return amount;
}

function applyWalletCredit({ wallet, amount }) {
  const state = walletState(wallet);
  const credit = normalizeTopUpAmount(amount);
  return walletState({
    ...state,
    balance: state.balance + credit,
  });
}

function applyWalletDebit({ wallet, amount }) {
  const state = walletState(wallet);
  const debit = positiveInteger(amount, "wallet debit");
  return walletState({
    ...state,
    balance: state.balance - debit,
  });
}

module.exports = {
  DEFAULT_LOW_BALANCE_THRESHOLD,
  MAX_TOP_UP_AMOUNT,
  WALLET_SCHEMA_VERSION,
  WALLET_STATUS_ACTIVE,
  WALLET_STATUS_SUSPENDED,
  applyWalletCredit,
  applyWalletDebit,
  estimatedPlatformFee,
  normalizeTopUpAmount,
  normalizeWalletStatus,
  walletRideEligibility,
  walletState,
};
