"use strict";

const { createHash } = require("node:crypto");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { buildUpdateMessage, passengerRideUpdate, validatePushToken } = require("./notification_logic");

const db = getFirestore();
const options = { region: "africa-south1", timeoutSeconds: 20, memory: "256MiB" };

exports.registerPassengerPushToken = onCall(options, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to enable notifications.");
  let token;
  try { token = validatePushToken(request.data?.token); }
  catch { throw new HttpsError("invalid-argument", "Invalid notification token."); }
  const uid = request.auth.uid;
  // An installation can belong to only one passenger account at a time.
  const ownerRef = db.collection("passenger_push_token_owners")
    .doc(createHash("sha256").update(token).digest("hex"));
  const tokenRef = db.collection("passenger_push_tokens").doc(uid);
  await db.runTransaction(async (tx) => {
    const account = await tx.get(db.collection("account_roles").doc(uid));
    if (account.get("deletionPending") === true) throw new HttpsError("failed-precondition", "This account is being deleted.");
    const owner = await tx.get(ownerRef);
    const previousUid = owner.get("uid");
    const previousRef = previousUid && previousUid !== uid
      ? db.collection("passenger_push_tokens").doc(previousUid) : null;
    const previous = previousRef ? await tx.get(previousRef) : null;
    if (previous?.get("token") === token) tx.delete(previousRef);
    tx.set(tokenRef, { token, updatedAt: FieldValue.serverTimestamp() });
    tx.set(ownerRef, { uid, updatedAt: FieldValue.serverTimestamp() });
  });
  return { registered: true };
});

async function sendAccountUpdate({ uid, driver = false, eventId, title, body, type }) {
  if (!uid) return;
  const tokenRef = db.collection(driver ? "driver_push_tokens" : "passenger_push_tokens").doc(uid);
  const snapshot = await tokenRef.get();
  const token = snapshot.get("token");
  if (!token) return;
  // Firestore events may be delivered more than once. Claim the event before
  // sending so retries cannot ring the same phone repeatedly.
  const deliveryRef = db.collection("notification_deliveries")
    .doc(createHash("sha256").update(`${driver}:${uid}:${eventId}`).digest("hex"));
  try {
    await deliveryRef.create({ createdAt: FieldValue.serverTimestamp(), eventId });
  } catch (error) {
    if (error.code === 6 || error.code === "already-exists") return;
    throw error;
  }
  try {
    await getMessaging().send(buildUpdateMessage({ token, eventId, title, body, type }));
    await deliveryRef.update({ deliveredAt: FieldValue.serverTimestamp() });
  } catch (error) {
    logger.warn("Account notification could not be delivered", { uid, eventId, code: error.code });
    await deliveryRef.update({ failedAt: FieldValue.serverTimestamp(), errorCode: error.code ?? "unknown" });
    if (["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(error.code)) {
      await db.runTransaction(async (tx) => {
        const current = await tx.get(tokenRef);
        if (current.get("token") === token) tx.delete(tokenRef);
      });
    }
  }
}

async function sendPublishedUpdate(event, driver) {
  const update = event.data?.data();
  if (!update || update.isRead === true || !["news", "discount"].includes(update.type)) return;
  // Historical inbox migration must not replay old promotional notifications.
  const created = update.createdAt?.toMillis?.();
  if (created && Date.now() - created > 5 * 60 * 1000) return;
  if (typeof update.title !== "string" || typeof update.message !== "string") return;
  await sendAccountUpdate({ uid: event.params.uid, driver,
    eventId: `${driver ? "driver" : "passenger"}:${event.params.notificationId}`,
    title: update.title, body: update.message, type: update.type });
}

exports.notifyPassengerInbox = onDocumentCreated(
  { ...options, document: "users/{uid}/notifications/{notificationId}" },
  (event) => sendPublishedUpdate(event, false),
);
exports.notifyDriverInbox = onDocumentCreated(
  { ...options, document: "drivers/{uid}/notifications/{notificationId}" },
  (event) => sendPublishedUpdate(event, true),
);
exports.notifyPassengerRideUpdate = onDocumentUpdated(
  { ...options, document: "rides/{rideId}" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const update = passengerRideUpdate(before, after);
    if (!update || !after.passengerId || after.bookingSource === "call_center") return;
    await sendAccountUpdate({ uid: after.passengerId,
      eventId: `ride:${event.params.rideId}:${after.status}`, ...update });
  },
);

