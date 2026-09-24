import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  getIdTokenResult,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  getFunctions,
  httpsCallable,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js";

const firebaseConfig = {
  apiKey: "AIzaSyBQfe36JwUXD4-Xq9_ky2IQD3mLwOORUhk",
  authDomain: "alpha-ride-29708.firebaseapp.com",
  projectId: "alpha-ride-29708",
  storageBucket: "alpha-ride-29708.firebasestorage.app",
  messagingSenderId: "486103357366",
  appId: "1:486103357366:web:98c3bd6fd18719067f1317",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const functions = getFunctions(app, "africa-south1");

const listDrivers = httpsCallable(functions, "adminListDrivers");
const creditWallet = httpsCallable(functions, "adminCreditDriverWallet");
const setWalletStatus = httpsCallable(
  functions,
  "adminSetDriverWalletStatus",
);
const setReviewStatus = httpsCallable(
  functions,
  "adminSetDriverReviewStatus",
);
const setVehicleClass = httpsCallable(
  functions,
  "adminSetDriverVehicleClass",
);
const listTransactions = httpsCallable(
  functions,
  "adminListWalletTransactions",
);

const elements = {
  loginView: document.querySelector("#login-view"),
  adminView: document.querySelector("#admin-view"),
  loginForm: document.querySelector("#login-form"),
  loginError: document.querySelector("#login-error"),
  email: document.querySelector("#email"),
  password: document.querySelector("#password"),
  adminEmail: document.querySelector("#admin-email"),
  signOut: document.querySelector("#sign-out"),
  refresh: document.querySelector("#refresh-drivers"),
  search: document.querySelector("#driver-search"),
  count: document.querySelector("#driver-count"),
  list: document.querySelector("#driver-list"),
  empty: document.querySelector("#empty-state"),
  detail: document.querySelector("#driver-detail"),
  name: document.querySelector("#driver-name"),
  meta: document.querySelector("#driver-meta"),
  reviewBadge: document.querySelector("#review-badge"),
  walletBalance: document.querySelector("#wallet-balance"),
  walletStatus: document.querySelector("#wallet-status"),
  walletCredits: document.querySelector("#wallet-credits"),
  walletDebits: document.querySelector("#wallet-debits"),
  vehicleType: document.querySelector("#vehicle-type"),
  plateNumber: document.querySelector("#plate-number"),
  vehicleClass: document.querySelector("#vehicle-class"),
  vehicleClassHint: document.querySelector("#vehicle-class-hint"),
  saveVehicleClass: document.querySelector("#save-vehicle-class"),
  topupForm: document.querySelector("#topup-form"),
  topupAmount: document.querySelector("#topup-amount"),
  topupReference: document.querySelector("#topup-reference"),
  topupNote: document.querySelector("#topup-note"),
  reviewStatus: document.querySelector("#review-status"),
  saveReview: document.querySelector("#save-review"),
  walletStatusSelect: document.querySelector("#wallet-status-select"),
  saveWalletStatus: document.querySelector("#save-wallet-status"),
  ledger: document.querySelector("#ledger-body"),
  toast: document.querySelector("#toast"),
};

let drivers = [];
let selectedDriverId = null;
let toastTimer = null;

function money(value) {
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 0,
  }).format(Number.isFinite(Number(value)) ? Number(value) : 0);
}

function readableError(error) {
  const message = typeof error?.message === "string" ? error.message : "";
  return message
    .replace(/^Firebase:\s*/i, "")
    .replace(/^Functions:\s*/i, "")
    .replace(/\s*\([^)]*\)\.?$/, "")
    .trim() || "The operation could not be completed.";
}

function vehicleClassLabel(value) {
  return {
    boda: "Boda",
    rickshaw: "Rickshaw",
    standard: "Standard",
    comfort: "Comfort",
    ev: "Electric",
    premium: "Premium",
    corporate: "Corporate",
  }[value] || "Unassigned";
}

function showToast(message) {
  clearTimeout(toastTimer);
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  toastTimer = setTimeout(() => {
    elements.toast.hidden = true;
  }, 4500);
}

function setBusy(button, busy) {
  button.disabled = busy;
  button.dataset.originalText ??= button.textContent;
  button.textContent = busy ? "Working…" : button.dataset.originalText;
}

function selectedDriver() {
  return drivers.find((driver) => driver.driverId === selectedDriverId) ?? null;
}

function searchableText(driver) {
  return [
    driver.firstName,
    driver.lastName,
    driver.phoneNumber,
    driver.plateNumber,
    driver.vehicleType,
    driver.vehicleClass,
    driver.driverId,
  ]
    .join(" ")
    .toLowerCase();
}

function renderDriverList() {
  const query = elements.search.value.trim().toLowerCase();
  const filtered = query
    ? drivers.filter((driver) => searchableText(driver).includes(query))
    : drivers;

  elements.count.textContent = `${filtered.length} of ${drivers.length} drivers`;
  elements.list.replaceChildren();

  for (const driver of filtered) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "driver-item";
    if (driver.driverId === selectedDriverId) button.classList.add("selected");

    const name = document.createElement("strong");
    name.textContent =
      `${driver.firstName ?? ""} ${driver.lastName ?? ""}`.trim() ||
      "Unnamed driver";
    const details = document.createElement("span");
    details.textContent = [
      driver.phoneNumber || "No phone",
      driver.reviewStatus || "pending",
      `${money(driver.wallet?.balance)} SSP`,
    ].join(" · ");

    button.append(name, details);
    button.addEventListener("click", () => selectDriver(driver.driverId));
    elements.list.append(button);
  }

  if (filtered.length === 0) {
    const message = document.createElement("p");
    message.className = "muted";
    message.textContent = "No drivers match this search.";
    elements.list.append(message);
  }
}

async function loadDrivers({ preserveSelection = true } = {}) {
  setBusy(elements.refresh, true);
  try {
    const result = await listDrivers({ limit: 100 });
    drivers = Array.isArray(result.data?.drivers) ? result.data.drivers : [];
    if (!preserveSelection) selectedDriverId = null;
    if (selectedDriverId && !selectedDriver()) selectedDriverId = null;
    renderDriverList();
    if (selectedDriverId) renderDriverDetail(selectedDriver());
  } catch (error) {
    showToast(readableError(error));
  } finally {
    setBusy(elements.refresh, false);
  }
}

async function selectDriver(driverId) {
  selectedDriverId = driverId;
  renderDriverList();
  const driver = selectedDriver();
  renderDriverDetail(driver);
  await loadLedger(driverId);
}

function renderDriverDetail(driver) {
  if (!driver) {
    elements.empty.hidden = false;
    elements.detail.hidden = true;
    return;
  }

  const wallet = driver.wallet ?? {};
  const fullName =
    `${driver.firstName ?? ""} ${driver.lastName ?? ""}`.trim() ||
    "Unnamed driver";
  elements.empty.hidden = true;
  elements.detail.hidden = false;
  elements.name.textContent = fullName;
  elements.meta.textContent = `${driver.phoneNumber || "No phone"} · ${driver.driverId}`;
  elements.reviewBadge.textContent = driver.reviewStatus || "pending";
  elements.walletBalance.textContent = `${money(wallet.balance)} ${wallet.currencyCode || "SSP"}`;
  elements.walletStatus.textContent =
    wallet.status === "suspended"
      ? "Suspended — cannot work"
      : wallet.balance <= 0
        ? "Recharge required"
        : wallet.isLowBalance
          ? "Low balance"
          : "Ready for rides";
  elements.walletCredits.textContent = `${money(wallet.lifetimeCredits)} SSP`;
  elements.walletDebits.textContent = `${money(wallet.lifetimeDebits)} SSP`;
  elements.vehicleType.textContent = driver.vehicleType || "Not recorded";
  elements.plateNumber.textContent = [
    driver.plateNumber || "No plate",
    `Alpha ${vehicleClassLabel(driver.vehicleClass)}`,
  ].join(" · ");
  elements.vehicleClass.value = driver.vehicleClass || "";
  elements.vehicleClass.disabled = !driver.requiresVehicleClass;
  elements.saveVehicleClass.disabled = !driver.requiresVehicleClass;
  elements.vehicleClassHint.textContent = driver.requiresVehicleClass
    ? driver.vehicleClass
      ? "Alpha administrators may update this class after reviewing the vehicle."
      : "Required before this regular vehicle can be approved."
    : `Automatically classified as ${vehicleClassLabel(driver.vehicleClass)}.`;
  elements.reviewStatus.value = driver.reviewStatus || "pending";
  elements.walletStatusSelect.value = wallet.status || "active";
}

async function loadLedger(driverId) {
  elements.ledger.replaceChildren();
  const loading = document.createElement("tr");
  const loadingCell = document.createElement("td");
  loadingCell.colSpan = 5;
  loadingCell.textContent = "Loading wallet history…";
  loading.append(loadingCell);
  elements.ledger.append(loading);

  try {
    const result = await listTransactions({ driverId });
    const transactions = Array.isArray(result.data?.transactions)
      ? result.data.transactions
      : [];
    elements.ledger.replaceChildren();

    if (transactions.length === 0) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 5;
      cell.textContent = "No wallet transactions yet.";
      row.append(cell);
      elements.ledger.append(row);
      return;
    }

    for (const item of transactions) {
      const row = document.createElement("tr");
      const createdAt = item.createdAtMillis
        ? new Date(item.createdAtMillis).toLocaleString()
        : "Pending";
      const isCredit = item.type === "top_up";
      const values = [
        createdAt,
        item.type === "ride_fee"
          ? "Ride fee"
          : item.type === "top_up"
            ? "Office recharge"
            : "Status change",
        `${isCredit ? "+" : item.amount ? "−" : ""}${money(item.amount)} ${item.currencyCode || "SSP"}`,
        `${money(item.balanceAfter)} ${item.currencyCode || "SSP"}`,
        item.reference || item.rideId || item.note || "—",
      ];
      values.forEach((value, index) => {
        const cell = document.createElement("td");
        cell.textContent = value;
        if (index === 2 && item.amount) {
          cell.className = isCredit ? "credit" : "debit";
        }
        row.append(cell);
      });
      elements.ledger.append(row);
    }
  } catch (error) {
    elements.ledger.replaceChildren();
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 5;
    cell.textContent = readableError(error);
    row.append(cell);
    elements.ledger.append(row);
  }
}

elements.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  elements.loginError.textContent = "";
  const button = elements.loginForm.querySelector("button");
  setBusy(button, true);
  try {
    await signInWithEmailAndPassword(
      auth,
      elements.email.value.trim(),
      elements.password.value,
    );
  } catch (error) {
    elements.loginError.textContent = readableError(error);
  } finally {
    setBusy(button, false);
  }
});

elements.signOut.addEventListener("click", () => signOut(auth));
elements.refresh.addEventListener("click", () => loadDrivers());
elements.search.addEventListener("input", renderDriverList);

elements.topupForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const driver = selectedDriver();
  if (!driver) return;
  const button = elements.topupForm.querySelector("button");
  setBusy(button, true);
  try {
    await creditWallet({
      driverId: driver.driverId,
      amount: Number(elements.topupAmount.value),
      reference: elements.topupReference.value.trim(),
      note: elements.topupNote.value.trim(),
    });
    elements.topupForm.reset();
    showToast("Wallet recharge recorded successfully.");
    await loadDrivers();
    await loadLedger(driver.driverId);
  } catch (error) {
    showToast(readableError(error));
  } finally {
    setBusy(button, false);
  }
});

elements.saveVehicleClass.addEventListener("click", async () => {
  const driver = selectedDriver();
  if (!driver || !driver.requiresVehicleClass) return;
  if (!elements.vehicleClass.value) {
    showToast("Select an Alpha ride class first.");
    return;
  }
  setBusy(elements.saveVehicleClass, true);
  try {
    await setVehicleClass({
      driverId: driver.driverId,
      vehicleClass: elements.vehicleClass.value,
    });
    showToast("Driver vehicle class updated.");
    await loadDrivers();
  } catch (error) {
    showToast(readableError(error));
  } finally {
    setBusy(elements.saveVehicleClass, false);
  }
});

elements.saveReview.addEventListener("click", async () => {
  const driver = selectedDriver();
  if (!driver) return;
  setBusy(elements.saveReview, true);
  try {
    await setReviewStatus({
      driverId: driver.driverId,
      reviewStatus: elements.reviewStatus.value,
      note: "Updated from Alpha Admin",
    });
    showToast("Driver review status updated.");
    await loadDrivers();
  } catch (error) {
    showToast(readableError(error));
  } finally {
    setBusy(elements.saveReview, false);
  }
});

elements.saveWalletStatus.addEventListener("click", async () => {
  const driver = selectedDriver();
  if (!driver) return;
  setBusy(elements.saveWalletStatus, true);
  try {
    await setWalletStatus({
      driverId: driver.driverId,
      status: elements.walletStatusSelect.value,
      note: "Updated from Alpha Admin",
    });
    showToast("Wallet status updated.");
    await loadDrivers();
    await loadLedger(driver.driverId);
  } catch (error) {
    showToast(readableError(error));
  } finally {
    setBusy(elements.saveWalletStatus, false);
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    elements.loginView.hidden = false;
    elements.adminView.hidden = true;
    elements.password.value = "";
    return;
  }

  try {
    const token = await getIdTokenResult(user, true);
    if (token.claims.admin !== true) {
      await signOut(auth);
      elements.loginError.textContent =
        "This account is not authorized for Alpha administration.";
      return;
    }
    elements.loginView.hidden = true;
    elements.adminView.hidden = false;
    elements.adminEmail.textContent = user.email || "Authorized administrator";
    await loadDrivers({ preserveSelection: false });
  } catch (error) {
    elements.loginError.textContent = readableError(error);
    await signOut(auth);
  }
});
