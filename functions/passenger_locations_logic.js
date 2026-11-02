"use strict";
const { createHash } = require("node:crypto");
const { haversineDistanceMeters, profileAllowsDispatch } = require("./dispatch_logic");
const { effectiveVehicleClassForProfile } = require("./vehicle_logic");
const ACTIVE = new Set(["accepted", "driver_arriving", "arrived", "in_progress"]);
function createPassengerLocations({ db, realtimeDb, HttpsError, limit, clock = Date.now }) {
  async function passenger(request) {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to see nearby vehicles.");
    const role = await db.collection("account_roles").doc(uid).get();
    if (role.get("role") !== "passenger" || role.get("deletionPending") === true) throw new HttpsError("permission-denied", "An active passenger account is required.");
    return uid;
  }
  function fresh(value) {
    const age = clock() - Number(value?.updatedAt ?? value?.lastUpdated);
    return value && typeof value.latitude === "number" && typeof value.longitude === "number" &&
      Number.isFinite(value.latitude) && Number.isFinite(value.longitude) &&
      Math.abs(value.latitude) <= 90 && Math.abs(value.longitude) <= 180 && age >= -10000 && age <= 90000;
  }
  async function nearby(request) {
    const uid = await passenger(request);
    const latitude = request.data?.latitude, longitude = request.data?.longitude;
    if (typeof latitude !== "number" || typeof longitude !== "number" || !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new HttpsError("invalid-argument", "Choose a valid map location.");
    await limit(uid, "nearby_locations", 30, 60000);
    const range = 12000 / 6371000 * 180 / Math.PI;
    const snapshot = await realtimeDb.ref("driver_locations").orderByChild("latitude")
      .startAt(Math.max(-90, latitude - range)).endAt(Math.min(90, latitude + range)).limitToFirst(200).get();
    const candidates = Object.entries(snapshot.val() || {}).filter(([, value]) => fresh(value) &&
      (value.isOnline === true || value.online === true) && !value.activeRideId &&
      haversineDistanceMeters({ latitude, longitude }, value) <= 12000);
    const refs = candidates.flatMap(([id]) => [db.collection("drivers").doc(id), db.collection("active_driver_rides").doc(id), db.collection("driver_wallets").doc(id)]);
    const profiles = refs.length ? await db.getAll(...refs) : [];
    const drivers = [];
    for (const [index, [id, value]] of candidates.entries()) {
      const [profile, lock, wallet] = profiles.slice(index * 3, index * 3 + 3);
      const vehicleType = effectiveVehicleClassForProfile(profile.data());
      const walletData = wallet.data() || {};
      if (lock.exists || !profileAllowsDispatch(profile.data(), vehicleType) ||
          !(Number(walletData.balance) > 0) || walletData.status === "suspended") continue;
      // Anonymous previews deliberately omit UID, ride/session IDs, phone,
      // exact position and exact update timestamps. Precise tracking is only
      // available through the separately authorized active-ride endpoint.
      const markerId = createHash("sha256").update(`${uid}:${Math.floor(clock() / 300000)}:${id}`).digest("hex").slice(0, 24);
      drivers.push({ driverId: `nearby_${markerId}`, latitude: Math.round(value.latitude * 1000) / 1000,
        longitude: Math.round(value.longitude * 1000) / 1000, heading: Math.round((Number(value.heading) || 0) / 30) * 30,
        vehicleType, isOnline: true, updatedAt: Math.floor(clock() / 15000) * 15000 });
      if (drivers.length === 40) break;
    }
    return { drivers, approximate: true };
  }
  async function assigned(request) {
    const uid = await passenger(request);
    await limit(uid, "assigned_location", 60, 60000);
    const lock = await db.collection("active_passenger_rides").doc(uid).get();
    const rideId = lock.get("rideId");
    if (typeof rideId !== "string" || !rideId || rideId.includes("/")) return { drivers: [] };
    const ride = await db.collection("rides").doc(rideId).get();
    const driverId = ride.get("driverId");
    if (ride.get("passengerId") !== uid || !ACTIVE.has(ride.get("status")) || typeof driverId !== "string" || !driverId || driverId.includes("/")) return { drivers: [] };
    if (request.data?.driverId !== driverId) throw new HttpsError("permission-denied", "Only your assigned driver can be tracked.");
    const point = (await realtimeDb.ref(`driver_locations/${driverId}`).get()).val();
    if (!fresh(point)) return { drivers: [] };
    return { drivers: [{ driverId, latitude: point.latitude, longitude: point.longitude, heading: Number(point.heading) || 0,
      vehicleType: ride.get("rideOptionId") || "standard", isOnline: true, updatedAt: Number(point.updatedAt ?? point.lastUpdated), activeRideId: rideId }] };
  }
  return { nearby, assigned };
}
module.exports = { createPassengerLocations };
