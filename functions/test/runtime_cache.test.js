"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { createTtlCache } = require("../runtime_cache");

test("runtime cache returns warm values until they expire", () => {
  let now = 1000;
  const cache = createTtlCache({
    ttlMs: 500,
    maxEntries: 4,
    clock: () => now,
  });

  cache.set("juba", ["airport"]);
  assert.deepEqual(cache.get("juba"), ["airport"]);
  now = 1500;
  assert.equal(cache.get("juba"), undefined);
  assert.equal(cache.size, 0);
});

test("runtime cache evicts the least recently used value", () => {
  const cache = createTtlCache({ ttlMs: 1000, maxEntries: 2 });
  cache.set("first", 1);
  cache.set("second", 2);
  assert.equal(cache.get("first"), 1);
  cache.set("third", 3);

  assert.equal(cache.get("second"), undefined);
  assert.equal(cache.get("first"), 1);
  assert.equal(cache.get("third"), 3);
});
