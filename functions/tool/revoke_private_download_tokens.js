"use strict";
// Run with Application Default Credentials for the Alpha project. Dry-run is
// the default; --apply revokes existing bearer download links. It does not
// delete images. Never print old tokens or URL query strings.
const { initializeApp } = require("firebase-admin/app");
const { getStorage } = require("firebase-admin/storage");
const projectId = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
if (projectId !== "alpha-ride-29708") throw new Error("Set GOOGLE_CLOUD_PROJECT=alpha-ride-29708 explicitly.");
initializeApp({ projectId, storageBucket: "alpha-ride-29708.firebasestorage.app" });
const apply = process.argv.includes("--apply");
(async () => {
  let examined = 0, revoked = 0;
  const bucket = getStorage().bucket();
  for (const prefix of ["user_photos/", "users/", "drivers/"]) {
    let pageToken;
    do {
      const [files, next] = await bucket.getFiles({ prefix, maxResults: 100, autoPaginate: false, ...(pageToken ? { pageToken } : {}) });
      for (const file of files) {
        const [metadata] = await file.getMetadata(); examined++;
        if (!metadata.metadata?.firebaseStorageDownloadTokens) continue;
        if (apply) await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } }, { ifMetagenerationMatch: metadata.metageneration });
        revoked++;
      }
      pageToken = next?.pageToken;
    } while (pageToken);
  }
  console.log(JSON.stringify({ dryRun: !apply, examined, linksToRevoke: revoked }));
})().catch(error => { console.error("Token migration did not finish:", error.code || "unknown"); process.exitCode = 1; });
