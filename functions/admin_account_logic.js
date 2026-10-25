"use strict";

const { randomUUID } = require("node:crypto");
const { hashPhoneNumber, normalizePhoneNumber } = require("./account_role_logic");
const TERMINAL = new Set(["completed", "cancelled", "expired", "no_driver_found"]);
const PRIVATE_COLLECTIONS = ["passenger_places_limits", "driver_photo_checks", "driver_ride_offers", "user_sessions",
  "driver_sessions", "driver_push_tokens", "passenger_push_tokens", "active_driver_rides", "active_passenger_rides"];

function createAdminAccountDeleter({ db, auth, storage, realtimeDb, HttpsError, now = () => new Date() }) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const ignoreMissingAuth = async (operation) => {
    try { return await operation(); }
    catch (error) { if (error.code !== "auth/user-not-found") throw error; return null; }
  };
  return async (request) => {
    if (!request.auth?.uid) fail("unauthenticated", "Sign in as an administrator.");
    if (request.auth.token?.admin !== true) fail("permission-denied", "Administrator access is required.");
    const { role, confirmPhone } = request.data || {};
    let uid = request.data?.uid;
    const legacySelection = role === "passenger" && typeof uid === "string" && uid === confirmPhone;
    if (legacySelection) {
      try { uid = (await auth.getUserByPhoneNumber(normalizePhoneNumber(confirmPhone))).uid; }
      catch { fail("failed-precondition", "This legacy registration needs its Firebase sign-in restored before deletion."); }
    }
    if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) || !["passenger", "driver"].includes(role)) {
      fail("invalid-argument", "Select a valid registered account.");
    }
    if (uid === request.auth.uid) fail("failed-precondition", "You cannot delete your own administrator account.");
    let phone;
    try { phone = normalizePhoneNumber(confirmPhone); }
    catch { fail("invalid-argument", "Enter the complete phone number, including the country code."); }
    const user = await ignoreMissingAuth(() => auth.getUser(uid));
    if (user?.customClaims?.admin || user?.customClaims?.customerService) {
      fail("failed-precondition", "Staff accounts cannot be deleted from this panel.");
    }
    const roleRef = db.collection("account_roles").doc(uid);
    const jobRef = db.collection("account_deletions").doc(uid);
    const profileRef = db.collection(role === "driver" ? "drivers" : "users").doc(uid);
    const phoneHash = hashPhoneNumber(phone);
    const identityRef = db.collection("identity_registry").doc(phoneHash);
    const legacyRef = db.collection("users").doc(phone);
    let deleteLegacy = false;
    let deleteLegacyPhoto = false;
    let alreadyDeleted = false;
    let acquired = false;
    const leaseId = randomUUID();
    // This transaction also fences new ride creation, acceptance and role claims.
    // It is intentionally retained across partial failures, making a retry safe.
    try {
      await db.runTransaction(async (tx) => {
        const [profile, binding, job, identity, legacy, driverLock, passengerLock, wallet] = await tx.getAll(
          profileRef, roleRef, jobRef, identityRef, legacyRef,
          db.collection("active_driver_rides").doc(uid), db.collection("active_passenger_rides").doc(uid),
          db.collection("driver_wallets").doc(uid),
        );
        const saved = job.data();
        if (saved && (saved.role !== role || saved.phoneHash !== phoneHash)) fail("failed-precondition", "This account has a different deletion request.");
        if (saved?.state === "completed") { alreadyDeleted = true; return; }
        if (Number(saved?.leaseExpiresAtMillis || 0) > now().getTime()) {
          fail("aborted", "Deletion is already running. Wait for it to finish before retrying this account.");
        }
        const canonicalPhone = user?.phoneNumber || profile.data()?.phoneNumber;
        if ((canonicalPhone && canonicalPhone !== phone) || (!canonicalPhone && saved?.phoneHash !== phoneHash)) {
          fail("failed-precondition", "The phone number does not match this account.");
        }
        if (!saved && !profile.exists && !(legacySelection && legacy.exists && user?.phoneNumber === phone)) fail("not-found", "This registered profile no longer exists.");
        if (binding.data()?.role && binding.data().role !== role) fail("failed-precondition", "The account type has changed. Refresh the list.");
        if (identity.exists && identity.data()?.uid && identity.data().uid !== uid && !saved) {
          fail("failed-precondition", "This number is linked to a different account. Refresh the list.");
        }
        for (const lock of [driverLock, passengerLock]) {
          if (!lock.exists) continue;
          const rideId = lock.data()?.rideId;
          if (typeof rideId !== "string" || !rideId) fail("failed-precondition", "Resolve this account's active ride before deleting it.");
          const ride = await tx.get(db.collection("rides").doc(rideId));
          if (!ride.exists || !TERMINAL.has(ride.data()?.status)) fail("failed-precondition", "Complete or cancel the active ride before deleting this account.");
        }
        if (wallet.exists && Number(wallet.data()?.balance ?? 0) !== 0) {
          fail("failed-precondition", "Settle the driver's wallet balance before deleting the account.");
        }
        deleteLegacy = role === "passenger" && legacy.exists &&
          (legacy.data()?.uid === uid || (!legacy.data()?.uid && user?.phoneNumber === phone));
        deleteLegacyPhoto = user?.phoneNumber === phone || saved?.verifiedPhone === true;
        tx.set(roleRef, { deletionPending: true }, { merge: true });
        if (profile.exists) tx.set(profileRef, { accountDeleting: true,
          ...(role === "driver" ? { reviewStatus: "deleting" } : {}) }, { merge: true });
        tx.set(jobRef, { role, phoneHash, state: "deleting", actorId: request.auth.uid,
          updatedAt: now(), leaseId, leaseExpiresAtMillis: now().getTime() + 180000, verifiedPhone: deleteLegacyPhoto, deleteLegacy: deleteLegacy || saved?.deleteLegacy === true }, { merge: true });
        deleteLegacy = deleteLegacy || saved?.deleteLegacy === true;
        acquired = true;
      });
      if (alreadyDeleted) return { deleted: true, uid, role };
      await ignoreMissingAuth(() => auth.updateUser(uid, { disabled: true }));
      await ignoreMissingAuth(() => auth.revokeRefreshTokens(uid));
      // A stale ID token must not put a deleted driver online again.
      await realtimeDb.ref(`account_deletions/${uid}`).set(true);
      await realtimeDb.ref(`driver_locations/${uid}`).remove();
      const bucket = storage.bucket();
      await bucket.deleteFiles({ prefix: `drivers/${uid}/` });
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
      if (role === "passenger" && deleteLegacyPhoto) await bucket.file(`user_photos/${phone}.jpg`).delete({ ignoreNotFound: true });
      for (const collection of PRIVATE_COLLECTIONS) await db.recursiveDelete(db.collection(collection).doc(uid));
      // Retain the profile roots until the final atomic commit. An interrupted
      // deletion remains visible in the admin list and can be retried there.
      const roots = [db.collection("users").doc(uid), db.collection("drivers").doc(uid)];
      if (deleteLegacy) roots.push(legacyRef);
      for (const root of roots) {
        for (const child of await root.listCollections()) await db.recursiveDelete(child);
      }
      // Token-owner documents are keyed by token hash rather than UID.
      for (const collection of ["passenger_push_token_owners"]) {
        const tokens = await db.collection(collection).where("uid", "==", uid).get();
        for (const token of tokens.docs) await db.runTransaction(async (tx) => {
          const owner = await tx.get(token.ref);
          if (owner.data()?.uid === uid) tx.delete(token.ref);
        });
      }
      await ignoreMissingAuth(() => auth.deleteUser(uid));
      await db.runTransaction(async (tx) => {
        const [identity, legacy] = await tx.getAll(identityRef, legacyRef);
        tx.delete(db.collection("users").doc(uid));
        tx.delete(db.collection("drivers").doc(uid));
        if (deleteLegacy && legacy.exists && (!legacy.data()?.uid || legacy.data()?.uid === uid) &&
            (!identity.exists || identity.data()?.uid === uid)) tx.delete(legacyRef);
        if (identity.exists && (identity.data()?.uid === uid || (!identity.data()?.uid && deleteLegacyPhoto))) tx.delete(identityRef);
        // Keep only a UID tombstone, without the phone hash or role, so a fresh
        // Auth UID can claim the number while old tokens cannot recreate data.
        tx.set(roleRef, { deletionPending: true, deleted: true, deletedAt: now() });
        tx.set(jobRef, { state: "completed", leaseId: null, leaseExpiresAtMillis: 0, updatedAt: now() }, { merge: true });
        tx.set(db.collection("admin_audit_log").doc(`account_delete_${uid}`), {
          action: "account_deleted", actorId: request.auth.uid, targetId: uid,
          role, phoneHash, createdAt: now(),
        });
      });
      return { deleted: true, uid, role };
    } catch (error) {
      if (acquired) {
        try {
          await db.runTransaction(async (tx) => {
            const job = await tx.get(jobRef);
            if (job.data()?.leaseId === leaseId) tx.set(jobRef,
              { leaseId: null, leaseExpiresAtMillis: 0 }, { merge: true });
          });
        } catch { /* A terminated instance's lease expires after three minutes. */ }
      }
      throw error;
    }
  };
}
module.exports = { createAdminAccountDeleter };

