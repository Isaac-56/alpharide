"use strict";
const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;
function createAdminDocumentLoader({ requireAdmin, db, storage, HttpsError }) {
  return async function loadDocument(request) {
    requireAdmin(request);
    const driverId = request.data?.driverId;
    const kind = request.data?.kind;
    if (typeof driverId !== "string" || !driverId.trim() || driverId.length > 128 || driverId.includes("/")) {
      throw new HttpsError("invalid-argument", "Choose a valid driver.");
    }
    if (!["front", "back", "identity"].includes(kind)) {
      throw new HttpsError("invalid-argument", "Choose a supported review document.");
    }
    const id = driverId.trim();
    const snapshot = await db.collection(kind === "identity" ? "driver_photo_checks" : "drivers").doc(id).get();
    const data = snapshot.data();
    const path = kind === "identity" ? data?.storagePath : data?.documents?.driverLicence?.[`${kind}StoragePath`];
    const prefix = `drivers/${id}/documents/${kind === "identity" ? "photo_checks" : "driver_licence"}/`;
    if (typeof path !== "string" || !path.startsWith(prefix) || path.includes("..") ||
        (!path.endsWith(".jpg") && !path.endsWith(".jpeg") && !path.endsWith(".png"))) {
      throw new HttpsError("not-found", "This driver has not uploaded that document.");
    }
    const file = storage.bucket().file(path);
    try {
      const [metadata] = await file.getMetadata();
      if (!Number.isFinite(Number(metadata.size)) || Number(metadata.size) <= 0 || Number(metadata.size) > MAX_DOCUMENT_BYTES) {
        throw new HttpsError("failed-precondition", "The document is empty or exceeds the image size limit.");
      }
      if (!["image/jpeg", "image/png"].includes(metadata.contentType)) {
        throw new HttpsError("failed-precondition", "The uploaded document is not a supported image.");
      }
      // Pin the metadata generation so a replaced file cannot bypass the limit.
      const [bytes] = await storage.bucket().file(path, { generation: metadata.generation }).download();
      if (bytes.length > MAX_DOCUMENT_BYTES) throw new HttpsError("failed-precondition", "The document exceeds the image size limit.");
      return { contentType: metadata.contentType, base64: bytes.toString("base64") };
    } catch (error) {
      if (Number(error.code) === 404) throw new HttpsError("not-found", "The uploaded image could not be found. Ask the driver to upload it again.");
      throw error;
    }
  };
}
module.exports = { createAdminDocumentLoader, MAX_DOCUMENT_BYTES };
