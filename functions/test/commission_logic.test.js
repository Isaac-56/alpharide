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
