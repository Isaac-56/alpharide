"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { createDispatchQueue, dispatchSchedule } = require("../dispatch_queue");
const ts = (ms) => ({ toMillis: () => ms });
function harness() {
  let current = { status: "requested", requestedAt: ts(1000) };
  const tasks = [];
  const runs = [];
  const handler = createDispatchQueue({
    db: { collection: () => ({ doc: () => ({ get: async () => ({ data: () => current }) }) }) },
    queue: { enqueue: async (data, options) => {
      if (tasks.some((task) => task.options.id === options.id)) {
        throw Object.assign(new Error("Duplicate"), { code: "functions/task-already-exists" });
      }
      tasks.push({ data, options });
    } },
    dispatchRide: async (data) => runs.push(data),
    clock: () => 2000,
  });
  const write = (before, after) => handler.onRideWritten({
    params: { rideId: "ride" },
    data: { before: { data: () => before }, after: { data: () => after } },
  });
  return { handler, write, tasks, runs, set: (data) => { current = data; }, get: () => current };
}
test("new request starts server matching with no passenger timer", async () => {
  const h = harness();
  await h.write(undefined, h.get());
  assert.equal(h.tasks.length, 1);
  assert.equal(h.tasks[0].options.scheduleTime.getTime(), 2000);
  await h.handler.processTask({ data: h.tasks[0].data });
  assert.deepEqual(h.runs, [{ rideId: "ride" }]);
});
test("no-driver retry and next offer wave use their exact server due times", async () => {
  const h = harness();
  for (const [round, due] of [[1, 5000], [2, 35000]]) {
    const before = h.get();
    h.set({ ...before, dispatchRound: round, offerExpiresAt: ts(due) });
    await h.write(before, h.get());
  }
  assert.deepEqual(h.tasks.map((t) => t.options.scheduleTime.getTime()), [5000, 35000]);
});
test("duplicate events enqueue once and unrelated writes enqueue nothing", async () => {
  const h = harness();
  await h.write(undefined, h.get());
  await h.write(undefined, h.get());
  await h.write(h.get(), { ...h.get(), updatedAt: ts(2000) });
  assert.equal(h.tasks.length, 1);
});
test("out-of-order event cannot schedule a cancelled or accepted ride", async () => {
  for (const status of ["cancelled", "accepted", "completed", "expired"]) {
    const h = harness();
    const old = h.get();
    h.set({ ...old, status });
    await h.write(undefined, old);
    assert.equal(h.tasks.length, 0);
  }
});
test("crashed dispatch resumes after its lease and never past search deadline", () => {
  const ride = { status: "requested", requestedAt: ts(1000), offerExpiresAt: ts(2000),
    dispatchLeaseUntil: ts(47000) };
  assert.equal(dispatchSchedule(ride).due, 47000);
  assert.equal(dispatchSchedule({ ...ride, dispatchDeadlineAt: ts(30000) }).due, 30000);
});
test("queue permission failures propagate so event delivery retries", async () => {
  const handler = createDispatchQueue({
    db: { collection: () => ({ doc: () => ({ get: async () => ({
      data: () => ({ status: "requested", requestedAt: ts(1000) }),
    }) }) }) },
    queue: { enqueue: async () => { throw new Error("permission denied"); } },
  });
  await assert.rejects(handler.schedule("ride"), /permission denied/);
});
test("worker failures propagate for task retry", async () => {
  const handler = createDispatchQueue({
    dispatchRide: async () => { throw new Error("temporary failure"); },
  });
  await assert.rejects(handler.processTask({ data: { rideId: "ride" } }), /temporary failure/);
  await assert.rejects(handler.processTask({ data: { rideId: "../bad" } }), /Invalid/);
});
