"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { commissionFilters, commissionDateMillis } = require("../commission_logic");
test("commission date boundaries include the whole Juba business day", () => {
  const filter = commissionFilters({ startDate: "2026-10-09", endDate: "2026-10-09", category: "Standard" });
  assert.equal(filter.category, "standard");
  assert.equal(filter.startMillis, Date.parse("2026-10-08T22:00:00Z"));
  assert.equal(filter.endMillis, Date.parse("2026-10-09T22:00:00Z"));
  assert.equal(filter.endMillis - filter.startMillis, 86400000);
});
test("commission dates reject invalid dates, reversed ranges and unknown services", () => {
  for (const date of ["2026-02-30", "2026-13-01", "2026-2-01", {}, 0]) assert.throws(() => commissionDateMillis(date));
  assert.throws(() => commissionFilters({ startDate: "2026-10-10", endDate: "2026-10-09" }));
  assert.throws(() => commissionFilters({ category: "unknown" }));
  assert.equal(commissionDateMillis("2024-02-29"), Date.parse("2024-02-28T22:00:00Z"));
});
test("cleared commission filters allow the full ledger", () => {
  assert.deepEqual(commissionFilters({ category: "", startDate: "", endDate: "" }), { category: "", startMillis: null, endMillis: null });
});
test("commission totals page the entire filtered ledger without an aggregate index", async () => {
  const { commissionQueryTotals } = require("../commission_logic");
  const docs = Array.from({ length: 501 }, (_, id) => ({ id, get: () => id === 500 ? 25 : 10 }));
  const offsets = [];
  function query(offset = 0) {
    return {
      select: () => query(offset),
      limit: () => query(offset),
      startAfter: (doc) => query(doc.id + 1),
      get: async () => { offsets.push(offset); const page = docs.slice(offset, offset + 500); return { docs: page, size: page.length }; },
    };
  }
  assert.deepEqual(await commissionQueryTotals(query()), { amount: 5025, count: 501 });
  assert.deepEqual(offsets, [0, 500]);
});
test("commission totals handle empty ledgers and receipts without numeric fees", async () => {
  const { commissionQueryTotals } = require("../commission_logic");
  const make = (fees) => ({ select() { return this; }, limit() { return this; }, async get() { return { size: fees.length, docs: fees.map((fee) => ({ get: () => fee })) }; } });
  assert.deepEqual(await commissionQueryTotals(make([])), { amount: 0, count: 0 });
  assert.deepEqual(await commissionQueryTotals(make([undefined, 20, NaN])), { amount: 20, count: 3 });
});
