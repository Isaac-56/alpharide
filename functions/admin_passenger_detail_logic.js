"use strict";

const MAX_PHOTO_BYTES = 6 * 1024 * 1024;
const text = (value) => typeof value === "string" ? value.trim() : "";
const millis = (value) => typeof value?.toMillis === "function" ? value.toMillis() : null;

function createAdminPassengerReader({ requireAdmin, db, auth, storage, HttpsError }) {
  async function account(request) {
    requireAdmin(request);
    const id = request.data?.passengerId;
    if (typeof id !== "string" || !id || id.length > 1500 || id.includes("/") || id.trim() !== id) {
      throw new HttpsError("invalid-argument", "Choose a valid passenger.");
    }
    const snapshot = await db.collection("users").doc(id).get();
    if (!snapshot.exists) throw new HttpsError("not-found", "Passenger profile not found. Refresh the directory.");
    const profile = snapshot.data();
    // Legacy profiles are keyed by phone; resolve their canonical Auth UID.
    let user = null;
    try {
      user = id.startsWith("+") ? await auth.getUserByPhoneNumber(id) : await auth.getUser(id);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    if (id.startsWith("+") && user) {
      const current = await db.collection("users").doc(user.uid).get();
      if (current.exists) return { id: user.uid, profile: current.data(), user };
    }
    return { id, profile, user };
  }

  async function detail(request) {
    const { id, profile, user } = await account(request);
    const lock = await db.collection("active_passenger_rides").doc(user?.uid || id).get();
    return {
      passengerId: id,
      name: text(profile.name) || [text(profile.firstName), text(profile.lastName)].filter(Boolean).join(" ") || "Passenger",
      phoneNumber: text(user?.phoneNumber) || text(profile.phoneNumber),
      phoneVerified: Boolean(user?.phoneNumber),
      email: text(profile.email), emergencyPhone: text(profile.emergencyPhone),
      referralCode: text(profile.referralCode),
      createdAtMillis: millis(profile.createdAt), updatedAtMillis: millis(profile.updatedAt),
      lastSignInAtMillis: user?.metadata?.lastSignInTime ? Date.parse(user.metadata.lastSignInTime) || null : null,
      accountDeleting: profile.accountDeleting === true,
      authStatus: !user ? "Sign-in record missing" : user.disabled ? "Disabled" : "Active",
      photoUploaded: Boolean(text(profile.photoStoragePath) || text(profile.photoUrl)),
      rideId: lock.exists ? text(lock.get("rideId")) : "",
    };
  }

  async function photo(request) {
    const { id, profile, user } = await account(request);
    const bucket = storage.bucket();
    let path = text(profile.photoStoragePath);
    if (!path && text(profile.photoUrl)) {
      try {
        const url = new URL(profile.photoUrl);
        const match = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
        if (url.protocol === "https:" && url.hostname === "firebasestorage.googleapis.com" && match &&
            decodeURIComponent(match[1]) === bucket.name) path = decodeURIComponent(match[2]);
      } catch { /* Never fetch arbitrary profile URLs. */ }
    }
    const uid = user?.uid || id;
    const legacyPhone = user?.phoneNumber;
    const owned = path.startsWith(`users/${uid}/profile/`) ||
      (legacyPhone && path === `user_photos/${legacyPhone}.jpg`);
    if (!owned || path.includes("..") || !/\.(jpe?g|png)$/i.test(path)) {
      throw new HttpsError("not-found", "No supported profile photo is available for this passenger.");
    }
    try {
      const [metadata] = await bucket.file(path).getMetadata();
      if (!Number.isFinite(Number(metadata.size)) || Number(metadata.size) <= 0 || Number(metadata.size) > MAX_PHOTO_BYTES ||
          !["image/jpeg", "image/png"].includes(metadata.contentType)) {
        throw new HttpsError("failed-precondition", "The profile photo is empty, unsupported or exceeds the image size limit.");
      }
      const [bytes] = await bucket.file(path, { generation: metadata.generation }).download();
      if (bytes.length > MAX_PHOTO_BYTES) throw new HttpsError("failed-precondition", "The profile photo exceeds the image size limit.");
      return { contentType: metadata.contentType, base64: bytes.toString("base64") };
    } catch (error) {
      if (Number(error.code) === 404) throw new HttpsError("not-found", "The profile photo could not be found.");
      throw error;
    }
  }
  return { detail, photo };
}

module.exports = { createAdminPassengerReader, MAX_PHOTO_BYTES };
