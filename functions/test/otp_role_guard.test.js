"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createOtpRoleGuard } = require("../otp_role_guard");
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function guard(data = {}) {
  let writes = 0;
  const db = {
    collection: c => ({ doc: id => ({ path: c + "/" + id }) }),
    runTransaction: fn => fn({
      async getAll(...refs) {
        return refs.map(ref => ({
          exists: Object.hasOwn(data, ref.path),
          get: field => data[ref.path]?.[field],
        }));
      },
      set() { writes++; },
    }),
  };
  return { run: createOtpRoleGuard({ db, HttpsError }), writes: () => writes };
}
test("canonical and legacy profiles reject the other product without writes", async () => {
  for (const [path, wanted] of [
    ["users/uid", "driver"], ["users/+211922049035", "driver"], ["drivers/uid", "passenger"],
  ]) {
    const g = guard({ [path]: {} });
    await assert.rejects(g.run("uid", "+211922049035", wanted), { code: "failed-precondition" });
    assert.equal(g.writes(), 0);
  }
});
test("new numbers remain unclaimed and matching roles can sign in", async () => {
  for (const data of [{}, { "account_roles/uid": { role: "driver" } }]) {
    const g = guard(data);
    await g.run("uid", "+211922049035", "driver");
    assert.equal(g.writes(), 0);
  }
});
test("conflicting profiles and deleting accounts fail closed", async () => {
  for (const data of [
    { "users/uid": {}, "drivers/uid": {} },
    { "account_roles/uid": { deletionPending: true } },
  ]) {
    await assert.rejects(guard(data).run("uid", "+211922049035", "driver"), { code: "failed-precondition" });
  }
});
