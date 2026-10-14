"use strict";

const { createHash } = require("node:crypto");
const SEARCH_WINDOW_MS = 180000;
const millis = (value) => typeof value?.toMillis === "function" ? value.toMillis() : null;

function dispatchSchedule(ride) {
  if (!ride || !["requested", "offered"].includes(ride.status)) return null;
  const requested = millis(ride.requestedAt);
  const due = millis(ride.offerExpiresAt) ?? requested;
  if (due === null) return null;
  const deadline = millis(ride.dispatchDeadlineAt) ?? (requested + SEARCH_WINDOW_MS);
  const lease = millis(ride.dispatchLeaseUntil) ?? 0;
  return {
    due: Math.min(deadline, Math.max(due, lease)),
    round: Number(ride.dispatchRound) || 0,
  };
}

function createDispatchQueue({ db, queue, dispatchRide, clock = Date.now }) {
  async function schedule(rideId) {
    // Read current state: Firestore events may be delivered out of order.
    const current = await db.collection("rides").doc(rideId).get();
    const next = dispatchSchedule(current.data());
    if (!next) return;
    const id = createHash("sha256")
      .update(`${rideId}:${next.round}:${next.due}`).digest("hex");
    try {
      await queue.enqueue({ rideId }, {
        id,
        scheduleTime: new Date(Math.max(clock(), next.due)),
        dispatchDeadlineSeconds: 60,
      });
    } catch (error) {
      if (error.code !== "functions/task-already-exists") throw error;
    }
  }

  async function onRideWritten(event) {
    const before = dispatchSchedule(event.data?.before.data());
    const after = dispatchSchedule(event.data?.after.data());
    if (!after || (before?.due === after.due && before?.round === after.round)) return;
    await schedule(event.params.rideId);
  }

  async function processTask(request) {
    const rideId = request.data?.rideId;
    if (typeof rideId !== "string" || !rideId || rideId.includes("/")) {
      throw new Error("Invalid dispatch task ride ID.");
    }
    await dispatchRide({ rideId });
    // A successful dispatch writes the next due time; the Firestore trigger
    // schedules that round. Terminal rides stop without creating another task.
  }

  return { onRideWritten, processTask, schedule };
}

module.exports = { createDispatchQueue, dispatchSchedule };
