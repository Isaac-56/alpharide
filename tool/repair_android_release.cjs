'use strict';
// Run on the release-building computer. No API keys or access tokens are printed.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const PROJECT = 'alpha-ride-29708';
const NUMBER = '486103357366';
const SHA1 = 'E6925D5F1CF1D5D3FE48B8BA766B729B06531858';
const SHA256 = '98E95355D511F68D2DC96A7580006E43E1C46A2C2E2E1541B01A08F46D795242';
const normalize = value => String(value || '').replace(/:/g, '').toUpperCase();
const apps = [
  { label: 'AlphaRide', folder: 'Alpha', package: 'com.alpharideapp.passengerapp', id: '1:486103357366:android:c53f304752a76ab17f1317' },
  { label: 'AlphaPlus', folder: 'alpha_plus', package: 'com.alpharide.driver', id: '1:486103357366:android:2326bbe4b1505b237f1317' },
];
function integrityPatch(config) {
  const wanted = {
    appIntegrity: { allowUnrecognizedVersion: true },
    accountDetails: { requireLicensed: false },
    deviceIntegrity: { minDeviceRecognitionLevel: 'MEETS_DEVICE_INTEGRITY' },
  };
  return config.appIntegrity?.allowUnrecognizedVersion === true &&
    config.accountDetails?.requireLicensed !== true &&
    config.deviceIntegrity?.minDeviceRecognitionLevel === 'MEETS_DEVICE_INTEGRITY'
    ? null : { name: config.name, ...wanted };
}
function mapsPatch(key, packageName) {
  const restrictions = key.restrictions || {};
  if (restrictions.browserKeyRestrictions || restrictions.serverKeyRestrictions || restrictions.iosKeyRestrictions) {
    throw new Error('This key is restricted for another platform. Configure a dedicated Android key; existing restrictions were not replaced.');
  }
  // Unrestricted keys already permit this certificate; do not narrow shared keys.
  if (!restrictions.androidKeyRestrictions) return null;
  const allowed = restrictions.androidKeyRestrictions.allowedApplications || [];
  if (allowed.some(app => app.packageName === packageName && normalize(app.sha1Fingerprint) === SHA1)) return null;
  if (!key.etag) throw new Error('Key has no concurrency token; refusing to overwrite restrictions.');
  return { name: key.name, etag: key.etag, restrictions: {
    ...restrictions,
    androidKeyRestrictions: { ...restrictions.androidKeyRestrictions,
      allowedApplications: [...allowed, { packageName, sha1Fingerprint: SHA1 }],
    },
  } };
}
function readConfig(repo, app) {
  const google = JSON.parse(fs.readFileSync(path.join(repo, 'android/app/google-services.json'), 'utf8'));
  const client = google.client.find(c => c.client_info?.android_client_info?.package_name === app.package);
  if (google.project_info?.project_id !== PROJECT || client?.client_info?.mobilesdk_app_id !== app.id) {
    throw new Error(`${app.label}: google-services.json does not match the expected Firebase app.`);
  }
  const options = fs.readFileSync(path.join(repo, 'lib/firebase_options.dart'), 'utf8');
  const android = options.match(/static const FirebaseOptions android = FirebaseOptions\(([\s\S]*?)\);/);
  if (!android || !android[1].includes(app.id) || !android[1].includes(PROJECT)) {
    throw new Error(`${app.label}: firebase_options.dart Android app identity does not match.`);
  }
  const firebaseKey = android[1].match(/apiKey:\s*['"]([^'"]+)['"]/)?.[1];
  const manifest = fs.readFileSync(path.join(repo, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
  const tag = manifest.match(/<meta-data\b[^>]*android:name="com\.google\.android\.geo\.API_KEY"[^>]*>/)?.[0];
  let mapsKey = tag?.match(/android:value="([^"]+)"/)?.[1];
  if (mapsKey === '${MAPS_API_KEY}') {
    const secrets = path.join(repo, 'android/secrets.properties');
    const text = fs.existsSync(secrets) ? fs.readFileSync(secrets, 'utf8') : '';
    mapsKey = text.match(/^\s*MAPS_API_KEY\s*=\s*(\S+)\s*$/m)?.[1] || process.env.MAPS_API_KEY;
  }
  if (![mapsKey, firebaseKey].every(k => /^AIza[\w-]+$/.test(k || ''))) {
    throw new Error(`${app.label}: cannot resolve the configured Maps/Firebase keys. No keys were changed.`);
  }
  return { mapsKey, firebaseKey };
}
function verifyApk(repo, app, sdk) {
  const apk = path.join(repo, 'build/app/outputs/flutter-apk/app-release.apk');
  if (!fs.existsSync(apk)) throw new Error(`${app.label}: release APK missing. Build it with your existing release keystore first.`);
  const toolsRoot = path.join(sdk, 'build-tools');
  const versions = fs.readdirSync(toolsRoot).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  const jar = versions.map(v => path.join(toolsRoot, v, 'lib/apksigner.jar')).find(fs.existsSync);
  if (!jar) throw new Error('Android SDK apksigner.jar not found. Install Android SDK Build-Tools.');
  const bundled = path.join(process.env.ProgramFiles || 'C:/Program Files', 'Android/Android Studio/jbr/bin/java.exe');
  const java = process.env.JAVA_HOME ? path.join(process.env.JAVA_HOME, 'bin', process.platform === 'win32' ? 'java.exe' : 'java')
    : fs.existsSync(bundled) ? bundled : 'java';
  let output;
  try { output = execFileSync(java, ['-jar', jar, 'verify', '--print-certs', apk], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] }); }
  catch { throw new Error(`${app.label}: APK signature verification failed.`); }
  const sha256 = output.match(/Signer #1 certificate SHA-256 digest:\s*([\da-f:]+)/i)?.[1];
  const sha1 = output.match(/Signer #1 certificate SHA-1 digest:\s*([\da-f:]+)/i)?.[1];
  if (normalize(sha256) !== SHA256 || normalize(sha1) !== SHA1) {
    throw new Error(`${app.label}: APK does not use the Alpha release certificate. Do not replace the existing signing key.`);
  }
  console.log(`${app.label}: release APK signature matches.`);
}
async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const verifyOnly = args.includes('--verify-signatures');
  const root = args.find(a => !a.startsWith('--')) || 'C:/Projects';
  const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || path.join(process.env.LOCALAPPDATA || '', 'Android/Sdk');
  const local = apps.map(app => {
    const repo = path.join(root, app.folder);
    verifyApk(repo, app, sdk);
    return { ...app, repo, ...readConfig(repo, app) };
  });
  if (verifyOnly) return;
  let token;
  try {
    // Fixed command only. Never interpolate keys, paths or user input into a shell.
    token = process.platform === 'win32'
      ? execFileSync('cmd.exe', ['/d', '/s', '/c', 'gcloud auth print-access-token'], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] }).trim()
      : execFileSync('gcloud', ['auth', 'print-access-token'], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch { throw new Error('Google Cloud login is needed. Run gcloud auth login with the Firebase project owner, then retry.'); }
  if (!token) throw new Error('Google Cloud returned no access token.');
  async function api(url, method = 'GET', body, allow404 = false) {
    let response;
    try { response = await fetch(url, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'x-goog-user-project': PROJECT },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(25000) }); }
    catch { throw new Error('Google Cloud request timed out or could not connect. Retry when the connection is stable.'); }
    if (allow404 && response.status === 404) return null;
    if (!response.ok) {
      let reason = '';
      let context = ` endpoint=${new URL(url).hostname}`;
      try {
        const data = await response.json();
        const known = ['SERVICE_DISABLED', 'BILLING_DISABLED', 'ACCESS_TOKEN_SCOPE_INSUFFICIENT', 'API_KEY_SERVICE_BLOCKED'];
        reason = data.error?.details?.map(d => d.reason).find(r => known.includes(r)) || '';
        for (const detail of data.error?.details || []) {
          const metadata = detail.metadata || {};
          if (/^[a-z0-9.-]+\.googleapis\.com$/.test(metadata.service || '')) context += ` service=${metadata.service}`;
          if (/^projects\/[a-z0-9-]+$/.test(metadata.consumer || '')) context += ` consumer=${metadata.consumer}`;
        }
      } catch { /* Never print provider error bodies, URLs or key strings. */ }
      throw new Error(`Google Cloud returned HTTP ${response.status} ${reason}.${context}. Verify the signed-in owner's permissions and enabled APIs; no automatic retry was made.`);
    }
    return response.json();
  }
  async function waitOperation(host, operation) {
    for (let i = 0; !operation.done && i < 30; i++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      operation = await api(`https://${host}/v1/${operation.name}`);
    }
    if (!operation.done || operation.error) throw new Error('Cloud operation did not complete successfully. Rerun to read the current state.');
  }
  for (const service of ['apikeys.googleapis.com', 'firebaseappcheck.googleapis.com', 'firebase.googleapis.com', 'playintegrity.googleapis.com', 'maps-android-backend.googleapis.com']) {
    const url = `https://serviceusage.googleapis.com/v1/projects/${NUMBER}/services/${service}`;
    const current = await api(url);
    if (current.state !== 'ENABLED') {
      if (!apply) throw new Error(`${service} is disabled. Run with --apply to enable the required API.`);
      await waitOperation('serviceusage.googleapis.com', await api(`${url}:enable`, 'POST', {}));
      console.log(`Enabled ${service}.`);
    }
  }
  const backup = path.join(os.homedir(), 'Alpha-Release-Config-Backups', new Date().toISOString().replace(/[:.]/g, '-'));
  function save(name, data) {
    fs.mkdirSync(backup, { recursive: true });
    fs.writeFileSync(path.join(backup, name + '.json'), JSON.stringify(data, null, 2));
  }
  let changes = 0;
  for (const app of local) {
    const shaUrl = `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}/androidApps/${app.id}/sha`;
    const certs = await api(shaUrl);
    for (const [certType, shaHash] of [['SHA_1', SHA1], ['SHA_256', SHA256]]) {
      if (!(certs.certificates || []).some(c => c.certType === certType && normalize(c.shaHash) === shaHash)) {
        changes++;
        if (apply) await api(shaUrl, 'POST', { certType, shaHash });
        console.log(`${app.label}: ${apply ? 'added' : 'needs'} release ${certType} in Firebase.`);
      }
    }
    const name = `projects/${NUMBER}/apps/${app.id}/playIntegrityConfig`;
    const url = `https://firebaseappcheck.googleapis.com/v1/${name}`;
    const config = await api(url, 'GET', undefined, true) || { name };
    const patch = integrityPatch(config);
    if (patch) {
      changes++;
      if (apply) {
        save(app.label + '-app-check', config);
        await api(`${url}?updateMask=appIntegrity,accountDetails,deviceIntegrity`, 'PATCH', patch);
        if (integrityPatch(await api(url))) throw new Error(`${app.label}: App Check settings did not match after saving.`);
      }
      console.log(`${app.label}: ${apply ? 'saved' : 'needs'} outside-Play settings with device integrity required.`);
    } else console.log(`${app.label}: App Check outside-Play settings already match.`);
    for (const [purpose, value] of [['Maps', app.mapsKey], ['Firebase', app.firebaseKey]]) {
      const lookup = await api(`https://apikeys.googleapis.com/v2/keys:lookupKey?keyString=${encodeURIComponent(value)}`);
      if (!lookup.name?.startsWith(`projects/${NUMBER}/locations/global/keys/`)) {
        throw new Error(`${app.label} ${purpose}: key belongs to another project. No cross-project changes were made.`);
      }
      const keyUrl = `https://apikeys.googleapis.com/v2/${lookup.name}`;
      const key = await api(keyUrl);
      if (purpose === 'Maps' && key.restrictions?.apiTargets?.length &&
          !key.restrictions.apiTargets.some(t => t.service === 'maps-android-backend.googleapis.com' && !t.methods?.length)) {
        throw new Error(`${app.label}: Maps SDK for Android is excluded by this key's API restrictions. Add it in Google Cloud Credentials; existing service restrictions were preserved.`);
      }
      const keyPatch = mapsPatch(key, app.package);
      if (keyPatch) {
        changes++;
        if (apply) {
          save(`${app.label}-${purpose}-key`, { name: key.name, restrictions: key.restrictions, etag: key.etag });
          let operation = await api(`${keyUrl}?updateMask=restrictions`, 'PATCH', keyPatch);
          for (let i = 0; !operation.done && i < 30; i++) {
            await new Promise(resolve => setTimeout(resolve, 1000));
            operation = await api(`https://apikeys.googleapis.com/v2/${operation.name}`);
          }
          if (!operation.done || operation.error || mapsPatch(await api(keyUrl), app.package)) {
            throw new Error(`${app.label}: key update was not confirmed. Rerun to check its current state.`);
          }
        }
        console.log(`${app.label} ${purpose}: ${apply ? 'added' : 'needs'} release SHA-1 restriction; previous entries preserved.`);
      } else console.log(`${app.label} ${purpose}: key restrictions permit this release certificate.`);
    }
  }
  token = null;
  if (!apply && changes) throw new Error('Review complete; run with --apply to repair the reported settings.');
  console.log('Configuration checks complete. Actual device attestation and map delivery still need a phone test.');
  if (apply && changes) console.log(`Previous settings saved in ${backup}`);
}
module.exports = { integrityPatch, mapsPatch, normalize, SHA1, SHA256, readConfig };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
