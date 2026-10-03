"use strict";

function createTtlCache({ ttlMs, maxEntries, clock = Date.now }) {
  if (!Number.isFinite(ttlMs) || ttlMs <= 0) {
    throw new RangeError("ttlMs must be positive");
  }
  if (!Number.isInteger(maxEntries) || maxEntries <= 0) {
    throw new RangeError("maxEntries must be a positive integer");
  }

  const entries = new Map();

  return Object.freeze({
    get(key) {
      const entry = entries.get(key);
      if (!entry) return undefined;
      if (entry.expiresAt <= clock()) {
        entries.delete(key);
        return undefined;
      }
      entries.delete(key);
      entries.set(key, entry);
      return entry.value;
    },
    set(key, value) {
      entries.delete(key);
      while (entries.size >= maxEntries) {
        entries.delete(entries.keys().next().value);
      }
      entries.set(key, { value, expiresAt: clock() + ttlMs });
      return value;
    },
    clear() {
      entries.clear();
    },
    get size() {
      return entries.size;
    },
  });
}

module.exports = { createTtlCache };
