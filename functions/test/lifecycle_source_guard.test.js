"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

test("completed ride settlement uses the transaction-scoped wallet result", () => {
  const source = readFileSync(
    join(__dirname, "..", "lifecycle_functions.js"),
    "utf8",
  );

  assert.doesNotMatch(source, /\bwalletAfter\b/);
  assert.match(source, /\bresolvedWalletAfter\b/);
});
