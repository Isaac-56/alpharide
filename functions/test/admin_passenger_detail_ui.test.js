"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { runInNewContext } = require("node:vm");
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function harness({ detail = async ({ passengerId }) => ({ data: { passengerId, name: passengerId, phoneNumber: "+211922222222", photoUploaded: false } }), photo = async () => ({ data: { contentType: "image/jpeg", base64: "AQID" } }) } = {}) {
  const nodes = new Map(), revoked = [], deletions = [];
  function $(id) {
    if (!nodes.has(id)) nodes.set(id, { hidden: false, disabled: false, dataset: {}, isConnected: true, textContent: "",
      removeAttribute(name) { delete this[name]; }, focus() {}, scrollIntoView() {},
      addEventListener(event, fn) { this[event] = fn; } });
    return nodes.get(id);
  }
  const context = { $, api: { passengerDetails: detail, passengerPhoto: photo }, auth: { currentUser: {} },
    passengerDetailRequestId: 0, passengerPhotoRequestId: 0, currentPassenger: null, passengerDetailTrigger: null,
    detailRows: (container, rows) => { container.rows = rows; }, dateTime: value => String(value),
    readableError: error => error.message, Blob, Uint8Array, atob: value => Buffer.from(value, "base64").toString("binary"),
    URL: { createObjectURL: () => "blob:private", revokeObjectURL: value => revoked.push(value) },
    deleteRegisteredAccount: data => deletions.push(data) };
  const source = readFileSync(join(__dirname, "../../admin/app.js"), "utf8");
  runInNewContext(source.slice(source.indexOf("function resetDocumentPreview"), source.indexOf("async function renderDocumentPreview")) +
    source.slice(source.indexOf("const passengerPhotoElements"), source.indexOf("function renderPassengers")), context);
  return { context, $, revoked, deletions };
}
test("passenger details open before deletion and the action targets the reviewed account", async () => {
  const h = harness(); await h.context.openPassengerDetail("passenger-a");
  assert.equal(h.$("#passenger-detail").hidden, false);
  assert.equal(h.$("#delete-passenger-account").disabled, false);
  h.$("#delete-passenger-account").click();
  assert.equal(h.deletions[0].uid, "passenger-a"); assert.equal(h.deletions[0].role, "passenger");
});
test("an older detail response cannot replace the newly selected passenger", async () => {
  const old = deferred(); const h = harness({ detail: ({ passengerId }) => passengerId === "old" ? old.promise : Promise.resolve({ data: { passengerId, name: "New passenger", phoneNumber: "+211922222222" } }) });
  const pending = h.context.openPassengerDetail("old"); await h.context.openPassengerDetail("new");
  old.resolve({ data: { passengerId: "old", name: "Old passenger" } }); await pending;
  assert.equal(h.$("#passenger-detail-title").textContent, "New passenger");
  assert.equal(h.context.currentPassenger.passengerId, "new");
});
test("failed details show retry and keep deletion disabled until the profile loads", async () => {
  const h = harness({ detail: async () => { throw new Error("Permission denied"); } });
  await h.context.openPassengerDetail("person");
  assert.equal(h.$("#retry-passenger-detail").hidden, false);
  assert.equal(h.$("#delete-passenger-account").disabled, true);
  assert.equal(h.$("#passenger-detail-status").textContent, "Permission denied");
});
test("closing details prevents a late photo response from exposing an old account image", async () => {
  const pendingPhoto = deferred(); const h = harness({ photo: () => pendingPhoto.promise });
  const pending = h.context.loadPassengerPhoto({ passengerId: "person", photoUploaded: true }, 0);
  h.context.closePassengerDetail();
  pendingPhoto.resolve({ data: { contentType: "image/jpeg", base64: "AQID" } }); await pending;
  assert.equal(h.$("#passenger-photo-image").src, undefined);
  assert.equal(h.$("#passenger-photo-link").hidden, true);
});
test("photo success waits for decode, then closing revokes its private URL", async () => {
  const h = harness(); await h.context.loadPassengerPhoto({ passengerId: "person", photoUploaded: true }, 0);
  assert.equal(h.$("#passenger-photo-link").hidden, true);
  h.$("#passenger-photo-image").onload(); assert.equal(h.$("#passenger-photo-link").hidden, false);
  h.context.closePassengerDetail(); assert.deepEqual(h.revoked, ["blob:private"]);
});
test("image failure and service failure both expose a retry without losing contact details", async () => {
  const h = harness(); await h.context.loadPassengerPhoto({ passengerId: "person", photoUploaded: true }, 0);
  h.$("#passenger-photo-image").onerror(); assert.equal(h.$("#retry-passenger-photo").hidden, false);
  const failed = harness({ photo: async () => { throw new Error("Photo timed out"); } });
  await failed.context.loadPassengerPhoto({ passengerId: "person", photoUploaded: true }, 0);
  assert.equal(failed.$("#passenger-photo-placeholder").textContent, "Photo timed out");
  assert.equal(failed.$("#retry-passenger-photo").hidden, false);
});
