import { readFileSync } from 'node:fs';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, get, set, update } from 'firebase/database';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';
import { ref as storageRef, getBytes, uploadBytes } from 'firebase/storage';
let env;
const projectId = 'demo-alpha-security';
before(async () => {
  env = await initializeTestEnvironment({ projectId,
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    database: { rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await env.clearDatabase(); await env.clearStorage(); });
const driver = () => env.authenticatedContext('driver', { phone_number: '+211922222222' });
const other = () => env.authenticatedContext('other', { phone_number: '+211933333333' });
async function seed() {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'account_roles/driver'), { role: 'driver' });
    await setDoc(doc(context.firestore(), 'drivers/driver'), { uid: 'driver', phoneNumber: '+211922222222', reviewStatus: 'approved' });
    await setDoc(doc(context.firestore(), 'driver_wallets/driver'), { balance: 10000 });
    await setDoc(doc(context.firestore(), 'rides/ride'), { driverId: 'driver', passengerId: 'passenger', status: 'accepted' });
    await set(ref(context.database(), 'driver_location_access/driver'), true);
    await set(ref(context.database(), 'driver_locations/driver'), { driverId: 'driver', presenceId: 'private-session-id', latitude: 4.85, longitude: 31.58, heading: 0, accuracy: 5, isOnline: true, vehicleType: 'boda', updatedAt: Date.now(), activeRideId: 'ride' });
  });
}
test('direct fleet reads and reads of another driver are denied, owner reads still work', async () => {
  await seed(); await assertFails(get(ref(other().database(), 'driver_locations')));
  await assertFails(get(ref(other().database(), 'driver_locations/driver')));
  await assertSucceeds(get(ref(driver().database(), 'driver_locations/driver')));
});
test('presence cannot be forged without a server-issued driver grant, with future timestamps or changed ride pointer', async () => {
  await seed();
  await assertFails(set(ref(other().database(), 'driver_locations/other'), { driverId: 'other', presenceId: 'some-session-123', latitude: 4.85, longitude: 31.58, heading: 0, accuracy: 5, isOnline: true, vehicleType: 'boda', updatedAt: Date.now() }));
  await assertFails(update(ref(driver().database(), 'driver_locations/driver'), { updatedAt: Date.now() + 86400000 }));
  await assertFails(update(ref(driver().database(), 'driver_locations/driver'), { activeRideId: 'other-ride' }));
  await assertSucceeds(update(ref(driver().database(), 'driver_locations/driver'), { latitude: 4.851, updatedAt: Date.now() }));
});
test('wallet, role, ride assignment and admin approval cannot be changed by a modified client', async () => {
  await seed(); const db = driver().firestore();
  await assertFails(updateDoc(doc(db, 'driver_wallets/driver'), { balance: 999999 }));
  await assertFails(setDoc(doc(db, 'account_roles/driver'), { role: 'admin' }));
  await assertFails(updateDoc(doc(db, 'rides/ride'), { finalFare: 1 }));
  await assertFails(updateDoc(doc(db, 'drivers/driver'), { reviewStatus: 'approved', reviewNote: 'fake approval' }));
  await assertFails(deleteDoc(doc(db, 'drivers/driver')));
  await assertFails(getDoc(doc(other().firestore(), 'rides/ride')));
});
test('legacy passenger photos are private and approved driver documents cannot be silently replaced', async () => {
  await seed(); const bytes = new Uint8Array([255, 216, 255, 217]);
  await env.withSecurityRulesDisabled(async context => {
    await uploadBytes(storageRef(context.storage(), 'user_photos/+211922222222.jpg'), bytes, { contentType: 'image/jpeg' });
    await uploadBytes(storageRef(context.storage(), 'drivers/driver/documents/photo_checks/selfie.jpg'), bytes, { contentType: 'image/jpeg' });
  });
  await assertSucceeds(getBytes(storageRef(driver().storage(), 'user_photos/+211922222222.jpg')));
  await assertFails(getBytes(storageRef(other().storage(), 'user_photos/+211922222222.jpg')));
  await assertFails(uploadBytes(storageRef(driver().storage(), 'drivers/driver/documents/driver_licence/front.jpg'), bytes, { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(storageRef(driver().storage(), 'drivers/driver/documents/photo_checks/selfie.jpg'), bytes, { contentType: 'image/jpeg' }));
});
test('deleted accounts cannot read their previous private data or republish presence', async () => {
  await seed(); await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'account_roles/driver'), { deletionPending: true });
    await set(ref(context.database(), 'account_deletions/driver'), true);
  });
  await assertFails(getDoc(doc(driver().firestore(), 'driver_wallets/driver')));
  await assertFails(get(ref(driver().database(), 'driver_locations/driver')));
  await assertFails(update(ref(driver().database(), 'driver_locations/driver'), { updatedAt: Date.now() }));
});
