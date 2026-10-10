"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { runInNewContext } = require("node:vm");
function harness(response = async () => ({ data: { base64: "AQID", contentType: "image/jpeg" } })) {
  const revoked = [];
  const context = { documentRenderId: 1, api: { driverDocument: response }, Blob, Uint8Array,
    atob: value => Buffer.from(value, "base64").toString("binary"),
    URL: { createObjectURL: () => "blob:private", revokeObjectURL: u => revoked.push(u) },
    readableError: e => e.message };
  const source = readFileSync(join(__dirname, "../../admin/app.js"), "utf8");
  runInNewContext(source.slice(source.indexOf("function resetDocumentPreview"), source.indexOf("function updateReviewButtonState")), context);
  const node = () => ({ hidden: false, dataset: {}, removeAttribute(name) { delete this[name]; } });
  const elements = { link: node(), image: node(), status: node(), placeholder: node() };
  return { context, revoked, ...elements,
    render: () => context.renderDocumentPreview({ path: "private.jpg", driverId: "driver", kind: "front", renderId: 1, ...elements }) };
}
test("document preview waits for image decoding before showing success", async () => {
  const h = harness(); await h.render();
  assert.equal(h.link.hidden, true);
  h.image.onload();
  assert.equal(h.link.hidden, false); assert.equal(h.placeholder.hidden, true);
  assert.equal(h.status.textContent, "Uploaded — open full size");
});
test("document failures leave a useful error instead of an indefinite spinner", async () => {
  const h = harness(async () => { throw new Error("The request timed out. Try again."); });
  await h.render(); assert.equal(h.status.textContent, "Image unavailable");
  assert.match(h.placeholder.textContent, /timed out/); assert.equal(h.link.hidden, true);
});
test("unreadable image bytes clear the preview and revoke its private URL", async () => {
  const h = harness(); await h.render(); h.image.onerror();
  assert.match(h.placeholder.textContent, /could not be displayed/);
  assert.deepEqual(h.revoked, ["blob:private"]);
});
test("changing drivers discards an older document response", async () => {
  let resolve;
  const h = harness(() => new Promise(r => { resolve = r; }));
  const pending = h.render(); h.context.documentRenderId = 2;
  resolve({ data: { base64: "AQID", contentType: "image/jpeg" } });
  await pending; assert.equal(h.image.src, undefined); assert.equal(h.link.hidden, true);
});
