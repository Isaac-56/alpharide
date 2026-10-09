"use strict";

const FINANCE_CATEGORIES = Object.freeze(["standard", "boda", "rickshaw", "comfort", "premium"]);
function commissionDateMillis(value, end = false) {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new TypeError("Invalid commission date.");
  const parsed = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString().slice(0, 10) !== value) throw new TypeError("Invalid commission date.");
  return parsed - 2 * 60 * 60 * 1000 + (end ? 24 * 60 * 60 * 1000 : 0);
}
function commissionFilters(input = {}) {
  const category = typeof input.category === "string" ? input.category.trim().toLowerCase() : "";
  if (category && !FINANCE_CATEGORIES.includes(category)) throw new TypeError("Invalid service category.");
  const startMillis = commissionDateMillis(input.startDate);
  const endMillis = commissionDateMillis(input.endDate, true);
  if (startMillis != null && endMillis != null && startMillis >= endMillis) throw new RangeError("Start date must precede end date.");
  return { category, startMillis, endMillis };
}
module.exports = { FINANCE_CATEGORIES, commissionFilters, commissionDateMillis };
