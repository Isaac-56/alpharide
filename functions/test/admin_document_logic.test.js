"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createAdminDocumentLoader, MAX_DOCUMENT_BYTES } = require("../admin_document_logic");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function harness({ path = "drivers/driver/documents/driver_licence/front.jpg", size = 3, contentType = "image/jpeg", missing = false } = {}) {
  let reads = 0;
  const paths = [];
  const loader = createAdminDocumentLoader({ HttpsError,
    requireAdmin: r => { if (!r.auth?.token?.admin) throw new HttpsError("permission-denied", "Admin required"); },
    db: { collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({
      documents: { driverLicence: { frontStoragePath: path, backStoragePath: path } }, storagePath: path,
    }) }) }) }) },
    storage: { bucket: () => ({ file: (name, options) => {
      paths.push({ name, options });
      return { getMetadata: async () => { reads++; if (missing) throw { code: 404 }; return [{ size, contentType, generation: "123" }]; },
        download: async () => { reads++; return [Buffer.from([1, 2, 3])]; } };
    } }) },
  });
  return { load: (data = { driverId: "driver", kind: "front" }, admin = true) => loader({ auth: { token: { admin } }, data }),
    reads: () => reads, paths };
}
test("administrator receives private image bytes pinned to metadata generation", async () => {
  const h = harness();
  assert.deepEqual(await h.load(), { contentType: "image/jpeg", base64: "AQID" });
  assert.deepEqual(h.paths[1].options, { generation: "123" });
});
test("non-admin requests cannot read storage", async () => {
  const h = harness(); await assert.rejects(h.load(undefined, false), e => e.code === "permission-denied"); assert.equal(h.reads(), 0);
});
test("invalid document kinds and driver IDs are rejected", async () => {
  const h = harness();
  for (const data of [{ driverId: "driver", kind: "arbitrary" }, { driverId: "../driver", kind: "front" }]) {
    await assert.rejects(h.load(data), e => e.code === "invalid-argument");
  }
  assert.equal(h.reads(), 0);
});
test("document paths cannot cross driver ownership or serve active content", async () => {
  for (const path of ["drivers/other/documents/driver_licence/front.jpg", "drivers/driver/documents/driver_licence/../secret.jpg", "drivers/driver/documents/driver_licence/front.svg"]) {
    const h = harness({ path }); await assert.rejects(h.load(), e => e.code === "not-found"); assert.equal(h.reads(), 0);
  }
});
test("identity photos use the driver photo-check record and directory", async () => {
  const h = harness({ path: "drivers/driver/documents/photo_checks/photo.jpg" });
  assert.equal((await h.load({ driverId: "driver", kind: "identity" })).base64, "AQID");
});
test("oversized, empty and unsupported images are rejected before downloading", async () => {
  for (const options of [{ size: MAX_DOCUMENT_BYTES + 1 }, { size: 0 }, { contentType: "text/html" }]) {
    const h = harness(options); await assert.rejects(h.load(), e => e.code === "failed-precondition"); assert.equal(h.reads(), 1);
  }
});
test("missing objects produce a clear re-upload error", async () => {
  const h = harness({ missing: true }); await assert.rejects(h.load(), e => e.code === "not-found" && e.message.includes("upload"));
});
