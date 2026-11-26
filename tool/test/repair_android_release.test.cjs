'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { integrityPatch, mapsPatch, SHA1 } = require('../repair_android_release.cjs');
test('outside-Play correction requires device integrity and preserves TTL via mask', () => {
  const before = { name: 'app', tokenTtl: '7200s', appIntegrity: { allowUnrecognizedVersion: false }, accountDetails: { requireLicensed: true } };
  const patch = integrityPatch(before);
  assert.deepEqual(patch, { name: 'app', appIntegrity: { allowUnrecognizedVersion: true }, accountDetails: { requireLicensed: false }, deviceIntegrity: { minDeviceRecognitionLevel: 'MEETS_DEVICE_INTEGRITY' } });
  assert.equal(integrityPatch(patch), null);
  assert.equal(before.appIntegrity.allowUnrecognizedVersion, false);
  assert.equal('tokenTtl' in patch, false);
});
test('adding the release cert retains old certs, other apps, API targets and etag', () => {
  const key = { name: 'key', etag: 'revision', restrictions: { apiTargets: [{ service: 'maps-android-backend.googleapis.com' }], androidKeyRestrictions: { allowedApplications: [{ packageName: 'old.app', sha1Fingerprint: 'ABC' }] } } };
  const patch = mapsPatch(key, 'com.alpharide.driver');
  assert.equal(patch.etag, 'revision');
  assert.deepEqual(patch.restrictions.apiTargets, key.restrictions.apiTargets);
  assert.deepEqual(patch.restrictions.androidKeyRestrictions.allowedApplications, [key.restrictions.androidKeyRestrictions.allowedApplications[0], { packageName: 'com.alpharide.driver', sha1Fingerprint: SHA1 }]);
  assert.equal(key.restrictions.androidKeyRestrictions.allowedApplications.length, 1);
  assert.equal(mapsPatch(patch, 'com.alpharide.driver'), null);
});
test('colon-separated fingerprints do not produce duplicate entries', () => {
  const key = { restrictions: { androidKeyRestrictions: { allowedApplications: [{ packageName: 'p', sha1Fingerprint: SHA1.match(/../g).join(':').toLowerCase() }] } } };
  assert.equal(mapsPatch(key, 'p'), null);
});
test('other platform restrictions cannot be replaced and unrestricted shared keys are unchanged', () => {
  for (const field of ['serverKeyRestrictions', 'browserKeyRestrictions', 'iosKeyRestrictions']) {
    assert.throws(() => mapsPatch({ restrictions: { [field]: {} } }, 'p'), /another platform/);
  }
  assert.equal(mapsPatch({ restrictions: { apiTargets: [{ service: 'example' }] } }, 'p'), null);
  assert.throws(() => mapsPatch({ restrictions: { androidKeyRestrictions: {} } }, 'p'), /concurrency/);
});
