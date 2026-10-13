"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { buildRideOfferMessage } = require("../notification_logic");
async function invalidPush({ refreshed = false } = {}) {
  let token = "old-driver-token-long-enough";
  let deleted = false;
  const context = { exports: {}, DRIVER_PUSH_TOKENS_COLLECTION: "driver_push_tokens", CURRENCY_CODE: "SSP", buildRideOfferMessage,
    logger: { warn() {} }, db: {
      collection: () => ({ doc: () => ({}) }),
      getAll: async () => [{ exists: true, get: () => token }],
      runTransaction: async (work) => work({ get: async () => ({ exists: true, get: () => token }), delete: () => { deleted = true; } }),
    }, messaging: { sendEach: async () => {
      if (refreshed) token = "new-driver-token-long-enough";
      return { responses: [{ success: false, error: { code: "messaging/registration-token-not-registered" } }] };
    } },
  };
  const source = fs.readFileSync(require.resolve("../index"), "utf8");
  vm.runInNewContext(source.slice(source.indexOf("async function sendRideOfferPushNotifications"), source.indexOf("exports.registerDriverPushToken")) +
    "\nexports.send = sendRideOfferPushNotifications;", context);
  await context.exports.send({ candidates: [{ driverId: "driver" }], rideId: "ride", rideOptionId: "boda", pickup: { address: "Pickup" }, estimatedFare: 1000 });
  return deleted;
}
test("a delayed invalid-token response cannot delete a freshly registered device token", async () => {
  assert.equal(await invalidPush({ refreshed: true }), false);
});
test("an unchanged invalid token is removed", async () => {
  assert.equal(await invalidPush(), true);
});
