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
// Use the same indexed receipt query for totals and rows. Sum aggregations add
// a separate platformFee index requirement and can fail while rows are readable.
async function commissionQueryTotals(query) {
  let amount = 0;
  let count = 0;
  let next = query.select("platformFee", "completedAt").limit(500);
  while (true) {
    const page = await next.get();
    for (const doc of page.docs) {
      const fee = doc.get("platformFee");
      if (typeof fee === "number" && Number.isFinite(fee)) amount += fee;
      count++;
    }
    if (page.size < 500) return { amount, count };
    next = query.select("platformFee", "completedAt").startAfter(page.docs.at(-1)).limit(500);
  }
}
module.exports = { commissionQueryTotals, FINANCE_CATEGORIES, commissionFilters, commissionDateMillis };
