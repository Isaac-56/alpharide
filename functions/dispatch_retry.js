"use strict";

const { randomUUID } = require("node:crypto");
const {
  DISPATCH_ALGORITHM_VERSION, MAX_DRIVER_OFFERS, OFFER_WINDOW_MS,
  selectPresenceCandidates, profileAllowsDispatch,
} = require("./dispatch_logic");
const { walletRideEligibility, estimatedPlatformFee } = require("./wallet_logic");
const { PLATFORM_COMMISSION_BPS } = require("./accounting_logic");

const SEARCH_WINDOW_MS = 180000;
const NO_CANDIDATE_RETRY_MS = 3000;
const LEASE_MS = 45000;
const UNANSWERED_RETRY_COOLDOWN_MS = 60000;
const MAX_OFFERS_PER_DRIVER = 2;
const searching = (status) => status === "requested" || status === "offered";
const ids = (value) => Array.isArray(value)
  ? [...new Set(value.filter((id) => typeof id === "string" && id && !id.includes("/")))] : [];
const millis = (value) => typeof value?.toMillis === "function" ? value.toMillis() : null;

function createDispatchEngine({ db, realtimeDb, Timestamp, FieldValue, sendPush, logger, clock = Date.now }) {
  const offerRef = (driverId, rideId) => db.collection("driver_ride_offers").doc(driverId).collection("offers").doc(rideId);

  async function dispatchRide({ rideId }) {
    const rideRef = db.collection("rides").doc(rideId);
    const token = randomUUID();
    const nowMs = clock();
    const claim = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(rideRef);
      if (!snapshot.exists) return { status: "missing" };
      const ride = snapshot.data();
      if (!searching(ride.status)) return { status: ride.status };
      const deadline = millis(ride.dispatchDeadlineAt) ??
        ((millis(ride.requestedAt) ?? nowMs) + SEARCH_WINDOW_MS);
      if (nowMs >= deadline) {
        const lockRef = db.collection("active_passenger_rides").doc(ride.passengerId);
        const lock = await tx.get(lockRef);
        for (const driverId of ids(ride.offeredDriverIds)) {
          tx.set(offerRef(driverId, rideId), { status: "expired", respondedAt: FieldValue.serverTimestamp() }, { merge: true });
        }
        tx.update(rideRef, { status: "expired", offerExpiresAt: null, dispatchLeaseUntil: null,
          dispatchState: "search_timeout", expiredAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
        if (lock.exists && lock.get("rideId") === rideId) tx.delete(lockRef);
        return { status: "expired" };
      }
      const due = millis(ride.offerExpiresAt);
      if ((due !== null && due > nowMs) || (millis(ride.dispatchLeaseUntil) ?? 0) > nowMs) {
        return { status: ride.status };
      }
      tx.update(rideRef, { dispatchLeaseToken: token,
        dispatchLeaseUntil: Timestamp.fromMillis(nowMs + LEASE_MS),
        dispatchDeadlineAt: Timestamp.fromMillis(deadline),
        // A crashed attempt remains visible to the scheduled recovery worker.
        offerExpiresAt: Timestamp.fromMillis(nowMs),
      });
      return { ride, deadline };
    });
    if (!claim.ride) return claim.status;
    const ride = claim.ride;
    const commissionBps = ride.platformCommissionBps ?? PLATFORM_COMMISSION_BPS;
    const attempted = ids(ride.attemptedDriverIds);
    const previousIds = ids(ride.offeredDriverIds);
    const lastOffers = ride.driverLastOfferAtMs ?? {};
    const offerCounts = ride.driverOfferCounts ?? {};
    const excluded = new Set(ids(ride.rejectedDriverIds));
    for (const driverId of new Set([...attempted, ...previousIds])) {
      const lastOffer = Number(lastOffers[driverId]) || millis(ride.dispatchAttemptedAt) || nowMs;
      const count = Number(offerCounts[driverId]) || 1;
      if (count >= MAX_OFFERS_PER_DRIVER || nowMs - lastOffer < UNANSWERED_RETRY_COOLDOWN_MS) {
        excluded.add(driverId);
      }
    }
    try {
      const presence = await realtimeDb.ref("driver_locations").get();
      const presenceMap = presence.exists() ? presence.val() : null;
      // Only examine fresh nearby drivers. A leftover terminal ride pointer
      // must not hide a driver before the authoritative lock check.
      const availableView = Object.fromEntries(Object.entries(presenceMap ?? {}).map(([id, value]) =>
        [id, value && typeof value === "object" ? { ...value, activeRideId: null } : value]));
      const nearby = selectPresenceCandidates({ presenceMap: availableView,
        pickup: ride.pickup, requiredVehicleType: ride.requiredVehicleType,
        nowMs: clock(), limit: Number.MAX_SAFE_INTEGER, excludedDriverIds: [...excluded] });
      await Promise.all(nearby.map(async ({ driverId }) => {
        const currentPresence = presenceMap[driverId];
        const previousRideId = currentPresence?.activeRideId;
        if (typeof previousRideId !== "string" || !previousRideId || previousRideId.includes("/")) return;
        const previousRideRef = db.collection("rides").doc(previousRideId);
        const lockRef = db.collection("active_driver_rides").doc(driverId);
        const released = await db.runTransaction(async (tx) => {
          const previousRide = await tx.get(previousRideRef);
          const lock = await tx.get(lockRef);
          if (!previousRide.exists || previousRide.get("driverId") !== driverId ||
              !["completed", "cancelled", "expired"].includes(previousRide.get("status")) ||
              (lock.exists && lock.get("rideId") !== previousRideId)) return false;
          if (lock.exists) tx.delete(lockRef);
          return true;
        });
        if (!released) return;
        const result = await realtimeDb.ref(`driver_locations/${driverId}`).transaction((current) => {
          if (!current || current.activeRideId !== previousRideId) return;
          const next = { ...current };
          delete next.activeRideId;
          return next;
        });
        // Use the committed value: a newer trip/session may have replaced it.
        if (result.committed) presenceMap[driverId] = result.snapshot.val();
      }));
      const candidates = selectPresenceCandidates({
        presenceMap,
        pickup: ride.pickup, requiredVehicleType: ride.requiredVehicleType,
        nowMs: clock(), limit: Number.MAX_SAFE_INTEGER, excludedDriverIds: [...excluded],
      });
      const verified = [];
      const exclusionCounts = { busy: 0, unapprovedOrWrongVehicle: 0, wallet: 0 };
      let scanned = 0;
      // Work outward in bounded reads; don't truncate before wallet eligibility.
      for (let offset = 0; offset < candidates.length && verified.length < MAX_DRIVER_OFFERS; offset += 25) {
        const chunk = candidates.slice(offset, offset + 25);
        const refs = chunk.flatMap((candidate) => [
          db.collection("drivers").doc(candidate.driverId),
          db.collection("active_driver_rides").doc(candidate.driverId),
          db.collection("driver_wallets").doc(candidate.driverId),
        ]);
        const snapshots = await db.getAll(...refs);
        for (const [index, candidate] of chunk.entries()) {
          scanned++;
          const [profile, lock, wallet] = snapshots.slice(index * 3, index * 3 + 3);
          if (lock.exists) { exclusionCounts.busy++; continue; }
          if (!profileAllowsDispatch(profile.data(), ride.requiredVehicleType)) {
            exclusionCounts.unapprovedOrWrongVehicle++; continue;
          }
          try {
            if (!walletRideEligibility({ wallet: wallet.data() ?? {}, estimatedFare: ride.estimatedFare, commissionBps }).allowed) {
              exclusionCounts.wallet++; continue;
            }
          } catch (error) {
            exclusionCounts.wallet++;
            logger.warn("Skipping malformed driver wallet", { driverId: candidate.driverId, error });
            continue;
          }
          verified.push(candidate);
        }
      }
      let offered = [];
      const result = await db.runTransaction(async (tx) => {
        offered = [];
        const current = await tx.get(rideRef);
        if (!current.exists || !searching(current.get("status")) || current.get("dispatchLeaseToken") !== token) {
          return current.exists ? current.get("status") : "missing";
        }
        const currentLocks = await Promise.all(verified.map((candidate) => tx.get(db.collection("active_driver_rides").doc(candidate.driverId))));
        offered = verified.filter((_, index) => !currentLocks[index].exists).slice(0, MAX_DRIVER_OFFERS);
        const commitMs = clock();
        if (commitMs >= claim.deadline) {
          // Leave recovery due; the next attempt atomically expires the search.
          tx.update(rideRef, { dispatchLeaseUntil: null, offerExpiresAt: Timestamp.fromMillis(commitMs) });
          offered = [];
          return current.get("status");
        }
        const expiry = Timestamp.fromMillis(Math.min(claim.deadline, commitMs + (offered.length ? OFFER_WINDOW_MS : NO_CANDIDATE_RETRY_MS)));
        for (const driverId of previousIds) {
          tx.set(offerRef(driverId, rideId), { status: "expired", respondedAt: FieldValue.serverTimestamp() }, { merge: true });
        }
        const round = (Number(current.get("dispatchRound")) || 0) + 1;
        for (const [index, candidate] of offered.entries()) {
          tx.set(offerRef(candidate.driverId, rideId), {
            schemaVersion: 1, rideId, driverId: candidate.driverId,
            passengerId: ride.passengerId, status: "pending",
            pickup: ride.pickup, destination: ride.destination,
            rideOptionId: ride.rideOptionId, requiredVehicleType: ride.requiredVehicleType,
            paymentMethod: ride.paymentMethod, estimatedFare: ride.estimatedFare,
            requiredWalletCredit: estimatedPlatformFee({ estimatedFare: ride.estimatedFare, commissionBps }),
            currencyCode: ride.currencyCode, bookingSource: ride.bookingSource ?? "app",
            distanceToPickupMeters: candidate.distanceToPickupMeters,
            dispatchRank: index + 1, dispatchRound: round,
            dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
            createdAt: FieldValue.serverTimestamp(), expiresAt: expiry, respondedAt: null,
          });
        }
        const driverIds = offered.map((candidate) => candidate.driverId);
        const nextLastOffers = { ...lastOffers };
        const nextOfferCounts = { ...offerCounts };
        for (const driverId of driverIds) {
          nextLastOffers[driverId] = commitMs;
          nextOfferCounts[driverId] = (Number(offerCounts[driverId]) || (attempted.includes(driverId) ? 1 : 0)) + 1;
        }
        const nextStatus = driverIds.length ? "offered" : "requested";
        tx.update(rideRef, {
          status: nextStatus, offeredDriverIds: driverIds,
          attemptedDriverIds: [...new Set([...attempted, ...previousIds, ...driverIds])],
          offerExpiresAt: expiry, dispatchLeaseUntil: null, dispatchRound: round,
          driverLastOfferAtMs: nextLastOffers, driverOfferCounts: nextOfferCounts,
          dispatchState: driverIds.length ? "offers_created" : "waiting_for_drivers",
          dispatchCandidateCount: driverIds.length, dispatchScannedCandidateCount: scanned,
          dispatchExclusionCounts: exclusionCounts,
          dispatchAlgorithmVersion: DISPATCH_ALGORITHM_VERSION,
          dispatchAttemptedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
        return nextStatus;
      });
      if (offered.length) {
        await sendPush({ candidates: offered, rideId, rideOptionId: ride.rideOptionId,
          pickup: ride.pickup, estimatedFare: ride.estimatedFare }).catch((error) => {
          logger.warn("Ride offers committed but push failed", { rideId, error });
        });
      }
      return result;
    } catch (error) {
      // Release only our lease. Never resurrect a cancelled or accepted ride.
      await db.runTransaction(async (tx) => {
        const current = await tx.get(rideRef);
        if (current.exists && searching(current.get("status")) && current.get("dispatchLeaseToken") === token) {
          tx.update(rideRef, { dispatchLeaseUntil: null,
            offerExpiresAt: Timestamp.fromMillis(clock() + NO_CANDIDATE_RETRY_MS), dispatchState: "retry_after_error" });
        }
      }).catch(() => {});
      throw error;
    }
  }
  return { dispatchRide };
}
module.exports = { createDispatchEngine, SEARCH_WINDOW_MS, NO_CANDIDATE_RETRY_MS };
