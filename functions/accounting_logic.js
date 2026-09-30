"use strict";

const ACCOUNTING_VERSION = 1;
const PLATFORM_COMMISSION_BPS = 1000;
const SETTLEMENT_STATUS_WALLET_DEDUCTED = "wallet_deducted";
const MAX_PLATFORM_COMMISSION_BPS = 5000;

function _positiveInteger(value, fieldName) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new RangeError(`${fieldName} must be a positive integer`);
  }
  return value;
}

function normalizeCommissionBps(value, fallback = PLATFORM_COMMISSION_BPS) {
  const normalized = Number(value);
  if (!Number.isInteger(normalized)) return fallback;
  if (normalized < 0 || normalized > MAX_PLATFORM_COMMISSION_BPS) {
    throw new RangeError("commissionBps must be between 0 and 5000");
  }
  return normalized;
}

function commissionBpsFromConfig(config = {}) {
  return normalizeCommissionBps(
    config && typeof config === "object" ? config.commissionBps : undefined,
  );
}

function calculateCompletedRideAccounting({
  grossFare,
  paymentMethod,
  commissionBps = PLATFORM_COMMISSION_BPS,
}) {
  const normalizedGrossFare = _positiveInteger(grossFare, "grossFare");
  const normalizedCommissionBps = normalizeCommissionBps(commissionBps);

  const normalizedPaymentMethod =
    typeof paymentMethod === "string" ? paymentMethod.trim().toLowerCase() : "";
  if (normalizedPaymentMethod !== "cash") {
    throw new RangeError("only cash ride accounting is enabled for launch");
  }

  const platformFee = Math.round(
    (normalizedGrossFare * normalizedCommissionBps) / 10000,
  );
  const driverNetFare = normalizedGrossFare - platformFee;

  return Object.freeze({
    accountingVersion: ACCOUNTING_VERSION,
    grossFare: normalizedGrossFare,
    platformCommissionBps: normalizedCommissionBps,
    platformFee,
    driverNetFare,
    cashCollectedByDriver: normalizedGrossFare,
    settlementStatus: SETTLEMENT_STATUS_WALLET_DEDUCTED,
  });
}

module.exports = {
  ACCOUNTING_VERSION,
  MAX_PLATFORM_COMMISSION_BPS,
  PLATFORM_COMMISSION_BPS,
  SETTLEMENT_STATUS_WALLET_DEDUCTED,
  calculateCompletedRideAccounting,
  commissionBpsFromConfig,
  normalizeCommissionBps,
};
