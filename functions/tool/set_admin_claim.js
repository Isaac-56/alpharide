"use strict";

const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

initializeApp();

async function main() {
  const email = process.argv[2]?.trim().toLowerCase();
  const mode = process.argv[3]?.trim().toLowerCase() || "grant";
  if (!email || !email.includes("@")) {
    throw new Error(
      "Usage: node tool/set_admin_claim.js <email> [grant|revoke]",
    );
  }
  if (!["grant", "revoke"].includes(mode)) {
    throw new Error("Mode must be grant or revoke.");
  }

  const auth = getAuth();
  const user = await auth.getUserByEmail(email);
  const claims = { ...(user.customClaims ?? {}) };

  if (mode === "grant") {
    claims.admin = true;
  } else {
    delete claims.admin;
  }

  await auth.setCustomUserClaims(user.uid, claims);
  console.log(
    `Admin access ${mode === "grant" ? "granted to" : "revoked from"} ${email}.`,
  );
  console.log("The user must sign out and sign in again to refresh the token.");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
