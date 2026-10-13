"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createRidePhotoLoader, passengerPhotoPath } = require("../ride_photo_logic");
const bucketName = "alpha-ride-29708.firebasestorage.app";
function harness({ signer } = {}) {
  const docs = new Map([
    ["rides/r1", { status: "accepted", passengerId: "p1", driverId: "d1", customerPhone: "+211912345678" }],
    ["driver_photo_checks/d1", { status: "approved", driverId: "d1", storagePath: "drivers/d1/documents/photo_checks/face.jpg" }],
    ["users/p1", { photoUrl: `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/user_photos%2F%2B211912345678.jpg?alt=media&token=old` }],
  ]);
  const downloaded = [];
  const storage = { bucket: () => ({ name: bucketName, file: (path, options) => ({
    getSignedUrl: signer,
    getMetadata: async () => [{ size: 10, contentType: "image/jpeg", generation: "3" }],
    download: async () => { downloaded.push({ path, options }); return [Buffer.from("photo-data")]; },
  }) }) };
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const load = createRidePhotoLoader({ storage, HttpsError,
    db: { collection: (name) => ({ doc: (id) => ({ get: async () => ({ exists: docs.has(`${name}/${id}`), data: () => docs.get(`${name}/${id}`) }) }) }) },
  });
  return { docs, downloaded, load: (uid, kind) => load({ auth: uid ? { uid } : null, data: { rideId: "r1" } }, kind) };
}
test("assigned passenger receives approved driver bytes without signing a URL", async () => {
  const h = harness(); const result = await h.load("p1", "driver");
  assert.equal(Buffer.from(result.imageBase64, "base64").toString(), "photo-data");
  assert.equal(h.downloaded[0].options.generation, "3");
});
test("assigned driver receives the passenger's current storage photo despite an old download token", async () => {
  const h = harness(); const result = await h.load("d1", "passenger");
  assert.ok(result.imageBase64);
  assert.equal(h.downloaded[0].path, "user_photos/+211912345678.jpg");
});
test("unrelated accounts cannot fetch either participant's private image", async () => {
  const h = harness();
  await assert.rejects(h.load("stranger", "driver"), { code: "permission-denied" });
  await assert.rejects(h.load("stranger", "passenger"), { code: "permission-denied" });
  await assert.rejects(h.load(null, "driver"), { code: "unauthenticated" });
  assert.equal(h.downloaded.length, 0);
});
test("unapproved selfies and inactive rides are never exposed as participant avatars", async () => {
  const h = harness(); h.docs.get("driver_photo_checks/d1").status = "pending";
  assert.equal((await h.load("p1", "driver")).imageBase64, "");
  h.docs.get("rides/r1").status = "cancelled";
  assert.equal((await h.load("d1", "passenger")).imageBase64, "");
});
test("foreign buckets, another phone's image and traversal paths are rejected", () => {
  const ride = { passengerId: "p1", customerPhone: "+211912345678" };
  for (const path of ["user_photos/+211999999999.jpg", "users/p2/photo.jpg", "users/p1/../p2.jpg"]) {
    assert.equal(passengerPhotoPath({ photoStoragePath: path }, ride, bucketName), "");
  }
  assert.equal(passengerPhotoPath({ photoUrl: "https://example.com/a.jpg" }, ride, bucketName), "");
});

test("a legacy URL signing failure cannot prevent authenticated photo bytes from loading", async () => {
  const h = harness({ signer: async () => { throw new Error("IAM signing is unavailable"); } });
  const image = await h.load("p1", "driver");
  assert.equal(image.photoUrl, "");
  assert.ok(image.imageBase64);
});


test("legacy APKs retain a signed photo URL where signing is available", async () => {
  const h = harness({ signer: async () => ["https://storage.googleapis.com/approved-photo?signature=test"] });
  const image = await h.load("p1", "driver");
  assert.ok(image.photoUrl.startsWith("https://"));
  assert.ok(image.expiresAtMillis > Date.now());
  assert.ok(image.imageBase64);
});
