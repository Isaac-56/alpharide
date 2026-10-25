"use strict";
const { approvedDriverPhotoStoragePath, validateRideId } = require("./dispatch_logic");
const MAX_PHOTO_BYTES = 6 * 1024 * 1024;

function passengerPhotoPath(profile, ride, bucketName) {
  const expected = ride.customerPhone ? `user_photos/${ride.customerPhone}.jpg` : "";
  const ownedPrefix = `users/${ride.passengerId}/`;
  let path = typeof profile?.photoStoragePath === "string" ? profile.photoStoragePath : "";
  if (!path && typeof profile?.photoUrl === "string") {
    try {
      const url = new URL(profile.photoUrl);
      if (url.protocol === "https:" && url.hostname === "firebasestorage.googleapis.com") {
        const match = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
        if (match && decodeURIComponent(match[1]) === bucketName) path = decodeURIComponent(match[2]);
      }
    } catch { return ""; }
  }
  if (path.includes("..") || !/\.(?:jpe?g|png|webp)$/i.test(path)) return "";
  return path && (path === expected || path.startsWith(ownedPrefix)) ? path : "";
}

function createRidePhotoLoader({ db, storage, auth, HttpsError }) {
  return async (request, kind) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to view this profile photo.");
    const rideId = validateRideId(request.data?.rideId);
    const snapshot = await db.collection("rides").doc(rideId).get();
    if (!snapshot.exists) throw new HttpsError("not-found", "This ride no longer exists.");
    const ride = snapshot.data();
    const viewer = kind === "driver" ? ride.passengerId : ride.driverId;
    if (viewer !== uid) throw new HttpsError("permission-denied", "Only the assigned ride participant can view this photo.");
    if (!["accepted", "driver_arriving", "arrived", "in_progress"].includes(ride.status)) {
      return { photoUrl: "", imageBase64: "" };
    }
    let path = "";
    const bucket = storage.bucket();
    if (kind === "driver") {
      const check = await db.collection("driver_photo_checks").doc(ride.driverId).get();
      path = approvedDriverPhotoStoragePath({ ride, passengerId: uid, photoCheck: check.data() });
    } else {
      let profile = await db.collection("users").doc(ride.passengerId).get();
      let verifiedPhone = ride.customerPhone;
      if (auth && (!verifiedPhone || !profile.exists)) {
        try { verifiedPhone = (await auth.getUser(ride.passengerId)).phoneNumber || verifiedPhone; }
        catch (error) { if (error.code !== "auth/user-not-found") throw error; }
      }
      if (!profile.exists && verifiedPhone) {
        const legacy = await db.collection("users").doc(verifiedPhone).get();
        if (!legacy.data()?.uid || legacy.data().uid === ride.passengerId) profile = legacy;
      }
      path = passengerPhotoPath(profile.data(), { ...ride, customerPhone: verifiedPhone }, bucket.name);
    }
    if (!path || path.includes("..")) return { photoUrl: "", imageBase64: "" };
    try {
      const [metadata] = await bucket.file(path).getMetadata();
      if (!Number.isFinite(Number(metadata.size)) || Number(metadata.size) <= 0 || Number(metadata.size) > MAX_PHOTO_BYTES ||
          !["image/jpeg", "image/png", "image/webp"].includes(metadata.contentType)) {
        throw new HttpsError("failed-precondition", "This profile image needs to be uploaded again.");
      }
      const [bytes] = await bucket.file(path, { generation: metadata.generation }).download();
      if (bytes.length > MAX_PHOTO_BYTES) throw new HttpsError("failed-precondition", "This profile image is too large.");
      // Older passenger APKs still read photoUrl. New APKs prefer the image
      // bytes, so missing IAM signing rights cannot break their photo display.
      let photoUrl = "";
      const expiresAtMillis = Date.now() + 10 * 60 * 1000;
      const file = bucket.file(path, { generation: metadata.generation });
      if (kind === "driver" && typeof file.getSignedUrl === "function") {
        try { [photoUrl] = await file.getSignedUrl({ action: "read", expires: expiresAtMillis }); }
        catch { /* Authenticated bytes remain available without a signer. */ }
      }
      return { photoUrl, expiresAtMillis: photoUrl ? expiresAtMillis : null,
        contentType: metadata.contentType, imageBase64: bytes.toString("base64") };
    } catch (error) {
      if (Number(error.code) === 404) return { photoUrl: "", imageBase64: "" };
      throw error;
    }
  };
}
module.exports = { createRidePhotoLoader, passengerPhotoPath };

