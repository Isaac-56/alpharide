"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createAdminPassengerReader, MAX_PHOTO_BYTES } = require("../admin_passenger_detail_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function harness(options = {}) {
  const files = [];
  const profile = { name: "A Passenger", phoneNumber: "+211900000000", email: "test@example.com", emergencyPhone: "+211911111111",
    photoStoragePath: "users/person/profile/photo.jpg", createdAt: { toMillis: () => 123 }, privateToken: "never-return", ...options.profile };
  const snapshot = (data) => ({ exists: Boolean(data), data: () => data, get: key => data?.[key] });
  const reads = [];
  const reader = createAdminPassengerReader({ HttpsError,
    requireAdmin: r => { if (!r.auth?.token?.admin) throw new HttpsError("permission-denied", "Admin required"); },
    db: { collection: collection => ({ doc: id => ({ get: async () => {
      reads.push(`${collection}/${id}`);
      return snapshot(collection === "users" ? options.missing ? null : profile : { rideId: "ride-123" });
    } }) }) },
    auth: { getUser: async uid => { if (options.authMissing) throw { code: "auth/user-not-found" };
      return { uid, phoneNumber: "+211922222222", metadata: { lastSignInTime: "2026-10-28T10:00:00Z" } }; },
    getUserByPhoneNumber: async () => ({ uid: "person", phoneNumber: "+211922222222" }) },
    storage: { bucket: () => ({ name: "bucket", file: (path, config) => {
      files.push({ path, config });
      return { getMetadata: async () => { if (options.storageMissing) throw { code: 404 };
        return [{ size: options.size ?? 3, contentType: options.contentType || "image/jpeg", generation: "42" }]; },
      download: async () => [options.download || Buffer.from([1, 2, 3])] };
    } }) },
  });
  const request = (passengerId = "person", admin = true) => ({ auth: { uid: "admin", token: { admin } }, data: { passengerId } });
  return { files, reads, detail: (id, admin) => reader.detail(request(id, admin)), photo: (id, admin) => reader.photo(request(id, admin)) };
}
test("passenger details include canonical phone, contact and registration without leaking raw profile fields", async () => {
  const h = harness(); const data = await h.detail();
  assert.equal(data.phoneNumber, "+211922222222"); assert.equal(data.phoneVerified, true);
  assert.equal(data.email, "test@example.com"); assert.equal(data.createdAtMillis, 123);
  assert.equal(data.rideId, "ride-123"); assert.equal(data.privateToken, undefined);
});
test("both detail and photo reject non-admins before database or storage reads", async () => {
  const h = harness();
  await assert.rejects(h.detail(undefined, false), e => e.code === "permission-denied");
  await assert.rejects(h.photo(undefined, false), e => e.code === "permission-denied");
  assert.equal(h.reads.length, 0); assert.equal(h.files.length, 0);
});
test("invalid IDs and missing profiles return useful errors", async () => {
  for (const id of ["", "../person", " person", "x".repeat(1501)]) {
    await assert.rejects(harness().detail(id), e => e.code === "invalid-argument");
  }
  await assert.rejects(harness({ missing: true }).detail(), e => e.code === "not-found");
});
test("legacy phone records resolve to the current UID profile and ride lock", async () => {
  const h = harness(); const data = await h.detail("+211922222222");
  assert.equal(data.passengerId, "person");
  assert.ok(h.reads.includes("active_passenger_rides/person"));
});
test("missing Auth record remains reviewable without inventing OTP verification", async () => {
  const data = await harness({ authMissing: true }).detail();
  assert.equal(data.phoneNumber, "+211900000000"); assert.equal(data.phoneVerified, false);
  assert.equal(data.authStatus, "Sign-in record missing");
});
test("private photo reads pin generation and return bounded bytes", async () => {
  const h = harness(); assert.deepEqual(await h.photo(), { contentType: "image/jpeg", base64: "AQID" });
  assert.deepEqual(h.files[1], { path: "users/person/profile/photo.jpg", config: { generation: "42" } });
});
test("cross-account, traversal and active-content photos cannot be read", async () => {
  for (const photoStoragePath of ["users/other/profile/photo.jpg", "users/person/profile/../secret.jpg", "users/person/profile/photo.svg", "user_photos/+211900000000.jpg"]) {
    const h = harness({ profile: { photoStoragePath } });
    await assert.rejects(h.photo(), e => e.code === "not-found"); assert.equal(h.files.length, 0);
  }
});
test("legacy photo URL accepts only this bucket and verified phone ownership", async () => {
  const h = harness({ profile: { photoStoragePath: "", photoUrl: "https://firebasestorage.googleapis.com/v0/b/bucket/o/user_photos%2F%2B211922222222.jpg?token=expired" } });
  assert.equal((await h.photo()).base64, "AQID");
  for (const photoUrl of ["https://evil.example/photo.jpg", "https://firebasestorage.googleapis.com/v0/b/other/o/users%2Fperson%2Fprofile%2Fphoto.jpg"]) {
    const denied = harness({ profile: { photoStoragePath: "", photoUrl } });
    await assert.rejects(denied.photo(), e => e.code === "not-found"); assert.equal(denied.files.length, 0);
  }
});
test("empty, oversized, unsupported or missing photos fail safely", async () => {
  for (const options of [{ size: 0 }, { size: MAX_PHOTO_BYTES + 1 }, { contentType: "text/html" }, { download: Buffer.alloc(MAX_PHOTO_BYTES + 1) }]) {
    await assert.rejects(harness(options).photo(), e => e.code === "failed-precondition");
  }
  await assert.rejects(harness({ storageMissing: true }).photo(), e => e.code === "not-found");
});
